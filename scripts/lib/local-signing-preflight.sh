#!/bin/bash

# A certificate listing cannot establish that its private key can sign.
# The caller owns a private temporary directory and its cleanup lifecycle.
narc_verify_local_signing() {
    local fingerprint="$1"
    local keychain="$2"
    local private_dir="$3"
    local codesign_bin="$4"
    local probe="${private_dir}/signing-probe"
    local sign_log="${private_dir}/signing-probe-sign.log"
    local verify_log="${private_dir}/signing-probe-verify.log"
    local requirement="identifier \"com.mickmi.narc.signing-probe\" and certificate leaf = H\"${fingerprint}\""
    local tool_status=0

    [[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]] \
        && [ -f "$keychain" ] && [ -x "$codesign_bin" ] \
        || { printf '❌ 签名预检参数无效。\n' >&2; return 1; }
    [ -d "$private_dir" ] && [ ! -L "$private_dir" ] \
        && [ "$(stat -f '%Lp' "$private_dir")" = "700" ] \
        && [ "$(stat -f '%u' "$private_dir")" = "$(id -u)" ] \
        || { printf '❌ 签名预检需要当前用户的私有临时目录。\n' >&2; return 1; }
    local path
    for path in "$probe" "$sign_log" "$verify_log"; do
        [ ! -e "$path" ] && [ ! -L "$path" ] \
            || { printf '❌ 签名预检临时路径已存在，未覆盖。\n' >&2; return 1; }
    done
    cp /usr/bin/true "$probe" \
        || { printf '❌ 无法准备临时签名检查。\n' >&2; return 1; }

    if "$codesign_bin" --force --sign "$fingerprint" --keychain "$keychain" \
        --identifier com.mickmi.narc.signing-probe --options runtime \
        --timestamp=none --requirements "=designated => ${requirement}" \
        "$probe" >"$sign_log" 2>&1; then
        :
    else
        tool_status=$?
        printf '❌ 本机自签预检失败（codesign exit %s）。证书存在，但私钥未能签名。\n' "$tool_status" >&2
        cat "$sign_log" >&2
        printf '请处理系统授权提示；若钥匙串已解锁仍报同一错误，请停止重复安装，恢复登录会话后再检查。\n' >&2
        return 1
    fi
    if "$codesign_bin" --verify --strict --test-requirement "=${requirement}" \
        "$probe" >"$verify_log" 2>&1; then
        :
    else
        tool_status=$?
        printf '❌ 本机自签验签失败（codesign exit %s），未确认所选身份可用。\n' "$tool_status" >&2
        cat "$verify_log" >&2
        return 1
    fi
    printf '✅ 本机临时签名与精确身份验签通过。\n' >&2
}
