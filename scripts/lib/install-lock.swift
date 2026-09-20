import Darwin

// Lock the descriptor opened by the parent shell, not a new file handle.
// BSD flock remains held while that inherited open description is alive.
guard CommandLine.arguments.count == 2,
      let descriptor = Int32(CommandLine.arguments[1]), descriptor >= 3 else {
    exit(64)
}
exit(flock(descriptor, LOCK_EX | LOCK_NB) == 0 ? 0 : 75)
