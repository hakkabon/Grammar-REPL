#include <editline/readline.h>

static inline void grammar_repl_set_completion(CPPFunction *function) {
    rl_attempted_completion_function = function;
}

static inline const char *grammar_repl_line_buffer(void) {
    return rl_line_buffer;
}
