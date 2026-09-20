#!/bin/bash

set -euo pipefail
umask 077
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

readonly LOCAL_IDENTITY_CN="NARC Local Code Signing Identity v1"
readonly LEGACY_IDENTITY_CN="NARC Dev"
readonly BUNDLE_ID="com.mickmi.narc"
readonly SECURITY_BIN="/usr/bin/security"
readonly CODESIGN_BIN="/usr/bin/codesign"
readonly OPENSSL_BIN="/usr/bin/openssl"
readonly MKTEMP_BIN="/usr/bin/mktemp"
readonly PLIST_BUDDY_BIN="/usr/libexec/PlistBuddy"

TEMP_DIR=""
LOGIN_KEYCHAIN=""
MARKER_DIR=""
MARKER_PATH=""
MARKER_PRESENT=0
MARKER_FINGERPRINT=""
MARKER_CREATED_THIS_RUN=0
MARKER_CREATED_INODE=""
SELECTED_IDENTITY_FINGERPRINT=""
SELECTED_IDENTITY_NAME=""
CREATED_IDENTITY_FINGERPRINT=""
CREATED_CERTIFICATE_PATH=""
ROLLBACK_CREATED_IDENTITY=0
ROLLBACK_CREATED_TRUST=0
STATE_COMMITTED=0
LOCAL_CERTIFICATE_FINGERPRINTS=()
VALID_IDENTITY_FINGERPRINTS=()
VALID_IDENTITY_NAMES=()
REQUEST_MODE="normal"
INSTALLED_APP_PATH=""
INSTALLED_APP_STATE="absent"
INSTALLED_APP_LEAF_FINGERPRINT=""
POLICY_ACTION=""
POLICY_FINGERPRINT=""
POLICY_IDENTITY_NAME=""
POLICY_ERROR=""
IDENTITY_MATCH_COUNT=0
IDENTITY_MATCH_NAME=""
NAME_MATCH_COUNT=0
NAME_MATCH_FINGERPRINT=""

note() {
    printf '%s\n' "$*" >&2
}

fail() {
    printf '❌ %s\n' "$*" >&2
    exit 1
}

cleanup() {
    local exit_code=$?
    local current_marker_inode=""
    local temp_suffix=""
    trap - EXIT

    if [ "$exit_code" -ne 0 ] && [ "$STATE_COMMITTED" -ne 1 ]; then
        if [ "$MARKER_CREATED_THIS_RUN" -eq 1 ] \
            && [ -n "$MARKER_CREATED_INODE" ] \
            && [ -f "$MARKER_PATH" ] \
            && [ ! -L "$MARKER_PATH" ]; then
            current_marker_inode="$(stat -f '%i' "$MARKER_PATH" 2>/dev/null || true)"
            if [ "$current_marker_inode" = "$MARKER_CREATED_INODE" ]; then
                rm -f -- "$MARKER_PATH" \
                    || printf '⚠️ 无法移除本轮创建的指纹标记：%s\n' "$MARKER_PATH" >&2
            else
                printf '⚠️ 指纹标记在运行期间被替换；为避免误删，已保留。\n' >&2
            fi
        fi

        if [ "$ROLLBACK_CREATED_IDENTITY" -eq 1 ] \
            && [[ "$CREATED_IDENTITY_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]] \
            && [ -n "$LOGIN_KEYCHAIN" ]; then
            note "↩️ 正在按本轮证书指纹回滚未完成的本地签名身份。"
            if [ "$ROLLBACK_CREATED_TRUST" -eq 1 ] \
                && [ -f "$CREATED_CERTIFICATE_PATH" ]; then
                "$SECURITY_BIN" remove-trusted-cert \
                    "$CREATED_CERTIFICATE_PATH" \
                    1>&2 \
                    || printf '⚠️ 无法移除本轮证书的用户级信任；请按指纹 %s 人工检查。\n' \
                        "$CREATED_IDENTITY_FINGERPRINT" >&2
            fi
            if ! "$SECURITY_BIN" delete-identity \
                -Z "$CREATED_IDENTITY_FINGERPRINT" \
                -t "$LOGIN_KEYCHAIN" \
                1>&2; then
                "$SECURITY_BIN" delete-certificate \
                    -Z "$CREATED_IDENTITY_FINGERPRINT" \
                    -t "$LOGIN_KEYCHAIN" \
                    1>&2 \
                    || printf '⚠️ 自动回滚失败；请按指纹 %s 人工检查登录钥匙串。\n' \
                        "$CREATED_IDENTITY_FINGERPRINT" >&2
            fi
        fi
    fi

    if [ -n "${TEMP_DIR:-}" ]; then
        temp_suffix="${TEMP_DIR#/private/tmp/narc-local-signing.}"
        if [ "$TEMP_DIR" != "$temp_suffix" ] \
            && [ -n "$temp_suffix" ] \
            && [[ "$temp_suffix" != */* ]] \
            && [ -d "$TEMP_DIR" ]; then
            chmod -R u+rwX "$TEMP_DIR" 2>/dev/null || true
            if ! rm -rf -- "$TEMP_DIR"; then
                printf '⚠️ 无法清理本轮私有临时目录：%s\n' "$TEMP_DIR" >&2
                exit_code=1
            fi
        else
            printf '⚠️ 临时目录路径未通过清理安全校验，未执行递归删除：%s\n' \
                "$TEMP_DIR" >&2
            exit_code=1
        fi
    fi

    exit "$exit_code"
}

require_runtime() {
    [ "$(uname -s)" = "Darwin" ] || fail "本地代码签名身份只能在 macOS 上创建。"
    [ "$(id -u)" -ne 0 ] || fail "请以当前登录用户运行，不要使用 sudo。"
    [ -n "${HOME:-}" ] && [ "${HOME#/}" != "$HOME" ] \
        || fail "无法确定当前用户的主目录。"

    local tool
    for tool in "$SECURITY_BIN" "$CODESIGN_BIN" "$OPENSSL_BIN" "$MKTEMP_BIN" "$PLIST_BUDDY_BIN"; do
        [ -x "$tool" ] || fail "缺少所需的 macOS 工具：$tool"
    done

    if [ -f "${HOME}/Library/Keychains/login.keychain-db" ]; then
        LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
    elif [ -f "${HOME}/Library/Keychains/login.keychain" ]; then
        LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain"
    else
        fail "未找到当前用户的登录钥匙串。请先登录 macOS 并打开一次“钥匙串访问”。"
    fi

    MARKER_DIR="${HOME}/Library/Application Support/NARC"
    MARKER_PATH="${MARKER_DIR}/signing-identity.sha1"
}

parse_arguments() {
    local restore_requested=0

    INSTALLED_APP_PATH="${NARC_INSTALL_DIR:-${HOME}/Applications}/NARC.app"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --installed-app)
                [ "$#" -ge 2 ] || fail "--installed-app 需要一个绝对路径。"
                INSTALLED_APP_PATH="$2"
                shift 2
                ;;
            --restore-legacy-signer)
                [ "$restore_requested" -eq 0 ] \
                    || fail "--restore-legacy-signer 不能重复指定。"
                REQUEST_MODE="restore-legacy"
                restore_requested=1
                shift
                ;;
            *)
                fail "未知参数：$1"
                ;;
        esac
    done

    case "$INSTALLED_APP_PATH" in
        /*) ;;
        *) fail "NARC App 路径必须是绝对路径。" ;;
    esac
    [ "$INSTALLED_APP_PATH" != "/" ] \
        || fail "NARC App 路径不能是文件系统根目录。"
}

install_cleanup_traps() {
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

create_private_temp_dir() {
    [ -d /private/tmp ] && [ -w /private/tmp ] \
        || fail "固定临时目录不可用：/private/tmp"

    TEMP_DIR="$($MKTEMP_BIN -d "/private/tmp/narc-local-signing.XXXXXX")" \
        || fail "无法创建临时目录。"
    chmod 700 "$TEMP_DIR" || fail "无法保护临时目录。"

    [ "$(stat -f '%Lp' "$TEMP_DIR")" = "700" ] \
        || fail "临时目录权限不是 0700。"
}

certificate_common_name() {
    local certificate_path="$1"
    local subject
    local part

    subject="$($OPENSSL_BIN x509 -in "$certificate_path" -noout -subject -nameopt RFC2253 2>/dev/null)" \
        || return 1
    subject="${subject#subject=}"
    subject="${subject#"${subject%%[![:space:]]*}"}"

    local old_ifs="$IFS"
    IFS=','
    for part in $subject; do
        part="${part#"${part%%[![:space:]]*}"}"
        if [[ "$part" == CN=* ]]; then
            IFS="$old_ifs"
            printf '%s\n' "${part#CN=}"
            return 0
        fi
    done
    IFS="$old_ifs"
    return 1
}

certificate_sha1() {
    local certificate_path="$1"
    local fingerprint

    fingerprint="$($OPENSSL_BIN x509 -in "$certificate_path" -noout -fingerprint -sha1 2>/dev/null)" \
        || return 1
    fingerprint="${fingerprint#*=}"
    fingerprint="${fingerprint//:/}"

    [[ "$fingerprint" =~ ^[0-9A-Fa-f]{40}$ ]] || return 1
    printf '%s' "$fingerprint" | tr '[:lower:]' '[:upper:]'
    printf '\n'
}

certificate_der_sha1() {
    local certificate_path="$1"
    local fingerprint

    fingerprint="$($OPENSSL_BIN x509 -inform DER -in "$certificate_path" -noout -fingerprint -sha1 2>/dev/null)" \
        || return 1
    fingerprint="${fingerprint#*=}"
    fingerprint="${fingerprint//:/}"

    [[ "$fingerprint" =~ ^[0-9A-Fa-f]{40}$ ]] || return 1
    printf '%s' "$fingerprint" | tr '[:lower:]' '[:upper:]'
    printf '\n'
}

inspect_installed_app() {
    local app_path="$1"
    local bundle_identifier=""
    local signature_details="${TEMP_DIR}/installed-signature.txt"
    local requirement_details="${TEMP_DIR}/installed-requirement.txt"
    local certificate_prefix="${TEMP_DIR}/installed-leaf"
    local leaf_certificate="${certificate_prefix}0"
    local actual_requirement=""
    local actual_requirement_upper=""
    local expected_requirement_upper=""

    INSTALLED_APP_STATE="absent"
    INSTALLED_APP_LEAF_FINGERPRINT=""

    [ ! -L "$app_path" ] \
        || fail "现有 NARC.app 不能是符号链接：$app_path"
    if [ ! -e "$app_path" ]; then
        return 0
    fi
    [ -d "$app_path" ] \
        || fail "现有 NARC.app 路径不是应用目录：$app_path"
    [ -f "$app_path/Contents/Info.plist" ] \
        || fail "现有 NARC.app 缺少 Info.plist；拒绝据此迁移签名。"

    bundle_identifier="$($PLIST_BUDDY_BIN -c 'Print :CFBundleIdentifier' \
        "$app_path/Contents/Info.plist" 2>/dev/null)" \
        || fail "无法读取现有 NARC.app 的 Bundle ID。"
    [ "$bundle_identifier" = "$BUNDLE_ID" ] \
        || fail "现有 App 的 Bundle ID 不是 ${BUNDLE_ID}；拒绝迁移签名。"

    "$CODESIGN_BIN" --verify --deep --strict "$app_path" \
        || fail "现有 NARC.app 未通过严格签名校验；拒绝迁移签名。"
    "$CODESIGN_BIN" --display --verbose=4 "$app_path" \
        >"$signature_details" 2>&1 \
        || fail "无法读取现有 NARC.app 的签名详情。"
    if grep -Fq 'Signature=adhoc' "$signature_details"; then
        INSTALLED_APP_STATE="adhoc"
        return 0
    fi

    "$CODESIGN_BIN" --display --extract-certificates="$certificate_prefix" "$app_path" \
        >"${TEMP_DIR}/extract-certificate.out" 2>&1 \
        || fail "无法提取现有 NARC.app 的公开叶证书。"
    [ -f "$leaf_certificate" ] \
        || fail "现有 NARC.app 没有可验证的公开叶证书。"
    INSTALLED_APP_LEAF_FINGERPRINT="$(certificate_der_sha1 "$leaf_certificate")" \
        || fail "无法读取现有 NARC.app 叶证书的 SHA-1 指纹。"

    "$CODESIGN_BIN" -d -r- "$app_path" >"$requirement_details" 2>&1 \
        || fail "无法读取现有 NARC.app 的 Designated Requirement。"
    actual_requirement="$(awk '
        /^designated => / { count += 1; requirement = $0 }
        END { if (count == 1) print requirement; else exit 1 }
    ' "$requirement_details")" \
        || fail "现有 NARC.app 必须且只能包含一个可解析的 Designated Requirement。"
    actual_requirement_upper="$(printf '%s' "$actual_requirement" | tr '[:lower:]' '[:upper:]')"
    expected_requirement_upper="$(printf '%s' \
        "designated => identifier \"${BUNDLE_ID}\" and certificate leaf = H\"${INSTALLED_APP_LEAF_FINGERPRINT}\"" \
        | tr '[:lower:]' '[:upper:]')"
    [ "$actual_requirement_upper" = "$expected_requirement_upper" ] \
        || fail "现有 NARC.app 的 Designated Requirement 不是精确的 Bundle ID + 叶证书约束；拒绝迁移。"

    "$CODESIGN_BIN" --verify --deep --strict \
        --test-requirement "=identifier \"${BUNDLE_ID}\" and certificate leaf = H\"${INSTALLED_APP_LEAF_FINGERPRINT}\"" \
        "$app_path" \
        || fail "现有 NARC.app 不满足其预期的稳定签名约束。"
    INSTALLED_APP_STATE="stable"
}

scan_matching_certificates() {
    local certificate_bundle="${TEMP_DIR}/matching-certificates.pem"
    local certificate_dir="${TEMP_DIR}/matching-certificates"
    local certificate_path
    local common_name
    local fingerprint

    LOCAL_CERTIFICATE_FINGERPRINTS=()
    mkdir -m 700 "$certificate_dir"

    if ! "$SECURITY_BIN" find-certificate -a -c "$LOCAL_IDENTITY_CN" -p "$LOGIN_KEYCHAIN" \
        >"$certificate_bundle" 2>"${TEMP_DIR}/find-certificate.err"; then
        fail "无法读取登录钥匙串中的证书。请确认钥匙串可用后重试。"
    fi

    if [ ! -s "$certificate_bundle" ]; then
        return 0
    fi

    /usr/bin/awk -v output_dir="$certificate_dir" '
        /-----BEGIN CERTIFICATE-----/ {
            certificate_count += 1
            output_file = sprintf("%s/certificate-%04d.pem", output_dir, certificate_count)
        }
        output_file != "" { print > output_file }
        /-----END CERTIFICATE-----/ {
            close(output_file)
            output_file = ""
        }
    ' "$certificate_bundle"

    for certificate_path in "$certificate_dir"/certificate-*.pem; do
        [ -e "$certificate_path" ] || continue
        common_name="$(certificate_common_name "$certificate_path")" \
            || fail "无法读取候选证书的 Common Name。"

        if [ "$common_name" = "$LOCAL_IDENTITY_CN" ]; then
            fingerprint="$(certificate_sha1 "$certificate_path")" \
                || fail "无法读取候选证书的 SHA-1 指纹。"
            LOCAL_CERTIFICATE_FINGERPRINTS+=("$fingerprint")
        fi
    done
}

scan_valid_identities() {
    local identity_listing="${TEMP_DIR}/valid-identities.txt"
    local identity_pattern='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"(.*)"$'
    local line
    local fingerprint
    local display_name

    VALID_IDENTITY_FINGERPRINTS=()
    VALID_IDENTITY_NAMES=()

    if ! "$SECURITY_BIN" find-identity -v -p codesigning "$LOGIN_KEYCHAIN" \
        >"$identity_listing" 2>"${TEMP_DIR}/find-identity.err"; then
        fail "无法读取登录钥匙串中的代码签名身份。请确认钥匙串已解锁。"
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ $identity_pattern ]]; then
            fingerprint="${BASH_REMATCH[1]}"
            display_name="${BASH_REMATCH[2]}"

            if [ "$display_name" = "$LOCAL_IDENTITY_CN" ] \
                || [ "$display_name" = "$LEGACY_IDENTITY_CN" ]; then
                fingerprint="$(printf '%s' "$fingerprint" | tr '[:lower:]' '[:upper:]')"
                VALID_IDENTITY_FINGERPRINTS+=("$fingerprint")
                VALID_IDENTITY_NAMES+=("$display_name")
            fi
        fi
    done <"$identity_listing"
}

reset_policy_result() {
    POLICY_ACTION=""
    POLICY_FINGERPRINT=""
    POLICY_IDENTITY_NAME=""
    POLICY_ERROR=""
}

policy_failure() {
    POLICY_ERROR="$1"
    return 1
}

find_identity_by_fingerprint() {
    local wanted_fingerprint="$1"
    local index=0

    IDENTITY_MATCH_COUNT=0
    IDENTITY_MATCH_NAME=""
    while [ "$index" -lt "${#VALID_IDENTITY_FINGERPRINTS[@]}" ]; do
        if [ "${VALID_IDENTITY_FINGERPRINTS[$index]}" = "$wanted_fingerprint" ]; then
            IDENTITY_MATCH_COUNT=$((IDENTITY_MATCH_COUNT + 1))
            IDENTITY_MATCH_NAME="${VALID_IDENTITY_NAMES[$index]}"
        fi
        index=$((index + 1))
    done
}

find_identity_by_name() {
    local wanted_name="$1"
    local excluded_fingerprint="${2:-}"
    local index=0

    NAME_MATCH_COUNT=0
    NAME_MATCH_FINGERPRINT=""
    while [ "$index" -lt "${#VALID_IDENTITY_NAMES[@]}" ]; do
        if [ "${VALID_IDENTITY_NAMES[$index]}" = "$wanted_name" ] \
            && [ "${VALID_IDENTITY_FINGERPRINTS[$index]}" != "$excluded_fingerprint" ]; then
            NAME_MATCH_COUNT=$((NAME_MATCH_COUNT + 1))
            NAME_MATCH_FINGERPRINT="${VALID_IDENTITY_FINGERPRINTS[$index]}"
        fi
        index=$((index + 1))
    done
}

# Pure policy selector. All macOS state is collected before this function so
# its migration decisions can be exhaustively tested without touching a real
# keychain, installed App, or TCC database.
determine_normal_signing_policy() {
    local marker_present="$1"
    local marker_fingerprint="$2"
    local installed_state="$3"
    local installed_leaf_fingerprint="$4"
    local local_certificate_count="$5"

    reset_policy_result

    if [ "$marker_present" -eq 1 ]; then
        find_identity_by_fingerprint "$marker_fingerprint"
        [ "$IDENTITY_MATCH_COUNT" -eq 1 ] \
            || policy_failure "指纹标记没有唯一对应的有效 NARC 本地身份；不会自动重建或轮换。" \
            || return 1
        case "$installed_state" in
            stable)
                [ "$installed_leaf_fingerprint" = "$marker_fingerprint" ] \
                    || policy_failure "现有 NARC.app 与指纹标记分别指向不同的稳定身份；不会静默覆盖或轮换。" \
                    || return 1
                ;;
            absent|adhoc) ;;
            *) policy_failure "现有 NARC.app 未通过 marker 连续性检查。"; return 1 ;;
        esac
        POLICY_ACTION="reuse-marker"
        POLICY_FINGERPRINT="$marker_fingerprint"
        POLICY_IDENTITY_NAME="$IDENTITY_MATCH_NAME"
        return 0
    fi

    if [ "$installed_state" = "stable" ]; then
        find_identity_by_fingerprint "$installed_leaf_fingerprint"
        [ "$IDENTITY_MATCH_COUNT" -eq 1 ] \
            || policy_failure "现有 NARC.app 的签名证书没有唯一对应的有效本地身份；不会猜测或轮换。" \
            || return 1
        POLICY_ACTION="adopt-installed"
        POLICY_FINGERPRINT="$installed_leaf_fingerprint"
        POLICY_IDENTITY_NAME="$IDENTITY_MATCH_NAME"
        return 0
    fi

    case "$installed_state" in
        absent|adhoc) ;;
        *) policy_failure "现有 NARC.app 未通过稳定签名迁移检查。"; return 1 ;;
    esac

    find_identity_by_name "$LOCAL_IDENTITY_CN"
    [ "$NAME_MATCH_COUNT" -le 1 ] \
        || policy_failure "登录钥匙串中存在多个有效的同名 NARC Local v1 身份；不会自动选取。" \
        || return 1
    if [ "$NAME_MATCH_COUNT" -eq 1 ]; then
        POLICY_ACTION="confirm-existing-local"
        POLICY_FINGERPRINT="$NAME_MATCH_FINGERPRINT"
        POLICY_IDENTITY_NAME="$LOCAL_IDENTITY_CN"
        return 0
    fi

    [ "$local_certificate_count" -eq 0 ] \
        || policy_failure "已存在 NARC Local v1 证书但没有唯一有效身份；不会自动重建或轮换。" \
        || return 1
    POLICY_ACTION="create-local-v1"
    POLICY_IDENTITY_NAME="$LOCAL_IDENTITY_CN"
    return 0
}

determine_legacy_restore_policy() {
    local marker_fingerprint="$1"
    local installed_leaf_fingerprint="$2"

    reset_policy_result
    [ -n "$marker_fingerprint" ] \
        || policy_failure "恢复旧签名要求当前指纹标记存在。" \
        || return 1
    [ "$installed_leaf_fingerprint" = "$marker_fingerprint" ] \
        || policy_failure "当前 NARC.app 与指纹标记不一致，拒绝恢复旧签名。" \
        || return 1

    find_identity_by_fingerprint "$marker_fingerprint"
    [ "$IDENTITY_MATCH_COUNT" -eq 1 ] \
        || policy_failure "当前指纹标记没有唯一对应的有效身份。" \
        || return 1

    find_identity_by_name "$LEGACY_IDENTITY_CN" "$marker_fingerprint"
    [ "$NAME_MATCH_COUNT" -eq 1 ] \
        || policy_failure "旧 NARC Dev 签名身份不是唯一且明确的有效候选。" \
        || return 1

    POLICY_ACTION="restore-legacy"
    POLICY_FINGERPRINT="$NAME_MATCH_FINGERPRINT"
    POLICY_IDENTITY_NAME="$LEGACY_IDENTITY_CN"
    return 0
}

scan_identity_state() {
    rm -rf -- "${TEMP_DIR}/matching-certificates"
    rm -f -- "${TEMP_DIR}/matching-certificates.pem" \
        "${TEMP_DIR}/find-certificate.err" \
        "${TEMP_DIR}/valid-identities.txt" \
        "${TEMP_DIR}/find-identity.err"
    scan_matching_certificates
    scan_valid_identities
}

read_fingerprint_marker() {
    local marker_line=""
    local extra_line=""

    MARKER_PRESENT=0
    MARKER_FINGERPRINT=""

    [ ! -L "$MARKER_PATH" ] \
        || fail "签名身份指纹标记不能是符号链接：$MARKER_PATH"
    if [ ! -e "$MARKER_PATH" ]; then
        return 0
    fi
    [ -f "$MARKER_PATH" ] \
        || fail "签名身份指纹标记不是普通文件：$MARKER_PATH"

    exec 3<"$MARKER_PATH" || fail "无法读取签名身份指纹标记。"
    if ! IFS= read -r marker_line <&3; then
        [ -n "$marker_line" ] || {
            exec 3<&-
            fail "签名身份指纹标记为空；不会自动重建身份。"
        }
    fi
    if IFS= read -r extra_line <&3 || [ -n "$extra_line" ]; then
        exec 3<&-
        fail "签名身份指纹标记必须且只能包含一行 SHA-1 指纹。"
    fi
    exec 3<&-

    [[ "$marker_line" =~ ^[0-9A-Fa-f]{40}$ ]] \
        || fail "签名身份指纹标记格式无效；不会自动重建身份。"
    MARKER_FINGERPRINT="$(printf '%s' "$marker_line" | tr '[:lower:]' '[:upper:]')"
    MARKER_PRESENT=1
}

write_fingerprint_marker() {
    local fingerprint="$1"

    [[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]] \
        || fail "拒绝写入格式无效的签名身份指纹。"
    [ ! -L "$MARKER_DIR" ] \
        || fail "NARC 应用数据目录不能是符号链接：$MARKER_DIR"
    mkdir -p "$MARKER_DIR" || fail "无法创建 NARC 应用数据目录。"
    [ -d "$MARKER_DIR" ] || fail "NARC 应用数据路径不是目录。"
    [ ! -e "$MARKER_PATH" ] && [ ! -L "$MARKER_PATH" ] \
        || fail "签名身份指纹标记已出现；为避免覆盖竞态，已停止。"

    if ! (set -o noclobber; printf '%s\n' "$fingerprint" >"$MARKER_PATH"); then
        fail "无法安全创建签名身份指纹标记。"
    fi
    MARKER_CREATED_THIS_RUN=1
    if ! MARKER_CREATED_INODE="$(stat -f '%i' "$MARKER_PATH")"; then
        rm -f -- "$MARKER_PATH" || true
        MARKER_CREATED_THIS_RUN=0
        fail "无法确认本轮创建的签名身份指纹标记。"
    fi
    chmod 600 "$MARKER_PATH" || fail "无法保护签名身份指纹标记。"
    MARKER_PRESENT=1
    MARKER_FINGERPRINT="$fingerprint"
}

create_identity() {
    local openssl_config="${TEMP_DIR}/openssl.cnf"
    local private_key="${TEMP_DIR}/identity.key"
    local certificate="${TEMP_DIR}/identity.pem"

    note "🔐 首次运行：正在为当前用户创建 NARC 本地代码签名身份。"

    printf '%s\n' \
        '[req]' \
        'prompt = no' \
        'distinguished_name = distinguished_name' \
        'x509_extensions = code_signing' \
        '' \
        '[distinguished_name]' \
        "CN = ${LOCAL_IDENTITY_CN}" \
        '' \
        '[code_signing]' \
        'basicConstraints = critical, CA:TRUE, pathlen:0' \
        'keyUsage = critical, digitalSignature, keyCertSign' \
        'extendedKeyUsage = critical, codeSigning' \
        'subjectKeyIdentifier = hash' \
        'authorityKeyIdentifier = keyid:always' \
        >"$openssl_config"

    if ! "$OPENSSL_BIN" req -new -newkey rsa:3072 -x509 -sha256 -nodes \
        -days 3650 \
        -config "$openssl_config" \
        -keyout "$private_key" \
        -out "$certificate" \
        >"${TEMP_DIR}/openssl-req.out" 2>"${TEMP_DIR}/openssl-req.err"; then
        fail "无法生成本地代码签名证书。"
    fi
    chmod 600 "$private_key" "$certificate"
    CREATED_IDENTITY_FINGERPRINT="$(certificate_sha1 "$certificate")" \
        || fail "无法确认本轮生成证书的 SHA-1 指纹。"
    CREATED_CERTIFICATE_PATH="$certificate"
    ROLLBACK_CREATED_IDENTITY=1

    note "📜 正在把自签名证书加入当前用户的登录钥匙串。"
    if ! "$SECURITY_BIN" add-certificates \
        -k "$LOGIN_KEYCHAIN" \
        "$certificate" \
        1>&2; then
        fail "证书导入失败；未回退到 ad-hoc。请检查登录钥匙串后重试。"
    fi
    note "🔑 正在导入当前用户的登录钥匙串；私钥将标记为不可导出。"
    if ! "$SECURITY_BIN" import "$private_key" \
        -k "$LOGIN_KEYCHAIN" \
        -x \
        -T /usr/bin/codesign \
        1>&2; then
        fail "身份导入失败；未回退到 ad-hoc。请检查登录钥匙串后重试。"
    fi

    note "🛡️ 正在添加仅限当前用户、仅限代码签名策略的信任。"
    ROLLBACK_CREATED_TRUST=1
    if ! "$SECURITY_BIN" add-trusted-cert \
        -r trustRoot \
        -p codeSign \
        -k "$LOGIN_KEYCHAIN" \
        "$certificate" \
        1>&2; then
        fail "用户级代码签名信任设置失败；未回退到 ad-hoc。请人工检查同名身份。"
    fi
}

main() {
    require_runtime
    parse_arguments "$@"
    install_cleanup_traps
    create_private_temp_dir
    read_fingerprint_marker
    scan_identity_state

    if [ "$REQUEST_MODE" = "restore-legacy" ]; then
        [ "$MARKER_PRESENT" -eq 1 ] \
            || fail "--restore-legacy-signer 要求当前签名指纹标记存在。"
        inspect_installed_app "$INSTALLED_APP_PATH"
        [ "$INSTALLED_APP_STATE" = "stable" ] \
            || fail "--restore-legacy-signer 要求当前 NARC.app 已由稳定本地身份签名。"
        determine_legacy_restore_policy \
            "$MARKER_FINGERPRINT" \
            "$INSTALLED_APP_LEAF_FINGERPRINT" \
            || fail "$POLICY_ERROR"

        [ -t 0 ] \
            || fail "恢复旧签名是显式交互操作；请在 Terminal 中直接运行安装命令。"
        note "⚠️ 即将把 NARC 从当前本地签名切回旧签名："
        note "   当前：${MARKER_FINGERPRINT}"
        note "   旧签名（${POLICY_IDENTITY_NAME}）：${POLICY_FINGERPRINT}"
        note "   这不会删除任何钥匙串身份，也不会重置辅助功能权限。"
        note "   若确认恢复，请输入上方旧签名的完整 40 位指纹："
        local restore_confirmation=""
        IFS= read -r restore_confirmation \
            || fail "未收到旧签名确认；没有修改 App 或指纹标记。"
        restore_confirmation="$(printf '%s' "$restore_confirmation" | tr '[:lower:]' '[:upper:]')"
        [ "$restore_confirmation" = "$POLICY_FINGERPRINT" ] \
            || fail "旧签名指纹确认不匹配；没有修改 App 或指纹标记。"
        printf '%s\n' "$POLICY_FINGERPRINT"
        return 0
    fi

    # An existing marker is the highest-priority continuity source, but the
    # installed App must not contradict it. A stable mismatch is exactly the
    # signer-rotation shape that breaks an existing TCC grant.
    if [ "$MARKER_PRESENT" -eq 1 ]; then
        inspect_installed_app "$INSTALLED_APP_PATH"
        determine_normal_signing_policy \
            "$MARKER_PRESENT" "$MARKER_FINGERPRINT" \
            "$INSTALLED_APP_STATE" "$INSTALLED_APP_LEAF_FINGERPRINT" \
            "${#LOCAL_CERTIFICATE_FINGERPRINTS[@]}" \
            || fail "$POLICY_ERROR"
        note "✅ 复用指纹已锁定的 NARC 本地代码签名身份（${POLICY_IDENTITY_NAME}）。"
        printf '%s\n' "$POLICY_FINGERPRINT"
        return 0
    fi

    inspect_installed_app "$INSTALLED_APP_PATH"
    determine_normal_signing_policy \
        "$MARKER_PRESENT" "$MARKER_FINGERPRINT" \
        "$INSTALLED_APP_STATE" "$INSTALLED_APP_LEAF_FINGERPRINT" \
        "${#LOCAL_CERTIFICATE_FINGERPRINTS[@]}" \
        || fail "$POLICY_ERROR"

    if [ "$POLICY_ACTION" = "adopt-installed" ]; then
        write_fingerprint_marker "$POLICY_FINGERPRINT"
        STATE_COMMITTED=1
        note "✅ 已沿用现有 NARC.app 的稳定本地签名（${POLICY_IDENTITY_NAME}）。"
        printf '%s\n' "$POLICY_FINGERPRINT"
        return 0
    fi

    if [ "$POLICY_ACTION" = "confirm-existing-local" ]; then
        [ -t 0 ] \
            || fail "发现未被指纹标记锁定的既有 NARC 本地身份；非交互环境不会自动采用来源未知的私钥。请在 Terminal 中重新运行安装命令。"
        note "⚠️ 发现一个未被本机标记锁定的既有 NARC 本地身份："
        note "   ${POLICY_FINGERPRINT}"
        note "   仅当这是你此前创建的 NARC 身份时，才输入上方完整指纹以确认复用。"
        local reuse_confirmation=""
        IFS= read -r reuse_confirmation \
            || fail "未收到复用确认；没有修改本机指纹标记。"
        reuse_confirmation="$(printf '%s' "$reuse_confirmation" | tr '[:lower:]' '[:upper:]')"
        [ "$reuse_confirmation" = "$POLICY_FINGERPRINT" ] \
            || fail "指纹确认不匹配；没有采用既有身份。"
        write_fingerprint_marker "$POLICY_FINGERPRINT"
        STATE_COMMITTED=1
        note "✅ 已按明确指纹确认复用既有 NARC 本地身份。"
        printf '%s\n' "$POLICY_FINGERPRINT"
        return 0
    fi

    [ "$POLICY_ACTION" = "create-local-v1" ] \
        || fail "未知的本地签名策略结果；为避免轮换，已停止。"

    create_identity
    scan_identity_state
    find_identity_by_name "$LOCAL_IDENTITY_CN"
    [ "$NAME_MATCH_COUNT" -eq 1 ] \
        || fail "身份已导入，但未能验证为唯一有效的 NARC Local v1 身份；请人工检查，脚本不会自动轮换。"
    SELECTED_IDENTITY_FINGERPRINT="$NAME_MATCH_FINGERPRINT"
    [ "$SELECTED_IDENTITY_FINGERPRINT" = "$CREATED_IDENTITY_FINGERPRINT" ] \
        || fail "验证到的唯一身份不是本轮生成的证书；已停止并回滚本轮随机指纹。"
    write_fingerprint_marker "$SELECTED_IDENTITY_FINGERPRINT"
    STATE_COMMITTED=1

    note "✅ NARC 本地代码签名身份已创建并验证。"
    printf '%s\n' "$SELECTED_IDENTITY_FINGERPRINT"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
