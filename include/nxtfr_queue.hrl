%% server state
-record(state, {
    limit :: integer(),
    head_pid :: pid(),
    tail_pid :: pid(),
    queue_size :: integer
    }).
-type state() :: #state{}.

%% queue process state
-record(queue_process_state, {
    ref :: reference(),
    connection_pid :: pid(),
    forward_pid :: pid(),
    back_pid :: pid(),
    queue_position :: integer()
    }).
-type queue_process_state() :: #queue_process_state{}.