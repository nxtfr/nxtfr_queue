-module(nxtfr_queue).
-author("christian@flodihn.se").
-behaviour(gen_server).

-define(QUEUE_PROCESS_OPTIONS, [
    {min_heap_size, 32}, % In a 64 bit system a word is 8 bytes, 32 words = 256 bytes 
    link
    ]).

%% server state
-record(state, {
    limit :: integer(),
    tail_pid :: pid(),
    head_pid :: pid(),
    queue_size :: integer
    }).
-type state() :: #state{}.

%% queue process tate
-record(queue_process_state, {
    ref :: reference(),
    forward_pid :: pid(),
    back_pid :: pid()
    }).
-type queue_process_state() :: #queue_process_state{}.

%% External exports
-export([
    start_link/1,
    dev/0,
    chain/1,
    info/0,
    set_limit/1,
    queue/0,
    dequeue/1
    ]).

%% gen_server callbacks
-export([
    init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2
    ]).

%% Internal exports
-export([
    queue_process_loop/1
    ]).

dev() ->
    application:start(nxtfr_queue),
    {ok, HeadPid, _} = nxtfr_queue:queue(),
    HeadPid.

chain(H) ->
    H ! chain.

start_link(Limit) ->
    gen_server:start_link({global, ?MODULE}, ?MODULE, [Limit], []).

-spec info() -> ok.
info() ->
    gen_server:call({global, ?MODULE}, info).

-spec set_limit(Limit :: integer()) -> ok.
set_limit(Limit) ->
    gen_server:call({global, ?MODULE}, {set_limit, Limit}).

-spec queue() -> {ok, QueuePid :: pid(), QueueNumber :: integer()}.
queue() ->
    gen_server:call({global, ?MODULE}, queue).

-spec dequeue(QueuePid :: pid()) -> ok.
dequeue(QueuePid) ->
    gen_server:call({global, ?MODULE}, {dequeue, QueuePid}).

-spec init([]) -> {ok, state()}.
init([Limit]) ->
    {ok, #state{limit = Limit, queue_size = 0}}.

handle_call(info, _From, State) ->
    {reply, State, State};

handle_call({set_limit, Limit}, _From, State) ->
    {reply, ok, State#state{limit = Limit}};

handle_call(queue, _From, #state{limit = Limit, queue_size = QueueSize} = State) when QueueSize >= Limit ->
    {reply, {error, queue_limit}, State};
    
% Match most frequent case when there is an existing head.
handle_call(queue, _From, #state{
        queue_size = QueueSize,
        tail_pid = TailPid,
        head_pid = HeadPid} = State) when is_pid(HeadPid) ->
    RequestPid = self(),
    QueueState = #queue_process_state {
        ref = make_ref(),
        forward_pid = TailPid
    },
    QueuePid = spawn_opt(?MODULE, queue_process_loop, [QueueState], ?QUEUE_PROCESS_OPTIONS),
    NewQueueSize = QueueSize + 1,
    ok = send_if_pid_valid(TailPid, {set_back_pid, QueuePid, RequestPid}, set_back_pid_ok),
    {reply, {ok, QueuePid, NewQueueSize}, State#state{
        queue_size = NewQueueSize,
        tail_pid = QueuePid}};

%% Match edge case when we are the first to be queued into an empty queue.
handle_call(queue, _From, #state{
        head_pid = undefined} = State) ->
    QueueState = #queue_process_state {
        ref = make_ref(),
        forward_pid = undefined,
        back_pid = undefined
    },
    QueuePid = spawn_opt(?MODULE, queue_process_loop, [QueueState], ?QUEUE_PROCESS_OPTIONS),
    NewQueueSize = 1,
    {reply, {ok, QueuePid, NewQueueSize}, State#state{
        queue_size = NewQueueSize,
        tail_pid = QueuePid,
        head_pid = QueuePid}};

%% Dequeueing a queue process in the middle should be most frequent, so we want to match it first.
handle_call({dequeue, QueuePid}, _From, #state{queue_size = QueueSize, head_pid = HeadPid} = State) 
        when QueuePid =/= HeadPid ->
    case dequeue_process(QueuePid) of
        ok ->
            NewQueueSize = QueueSize - 1,
            {reply, ok, State#state{queue_size = NewQueueSize}};
        {error, timeout} ->
            {reply, {error, timeout}, State}
    end;

%% Match edge case when dequeing last process (tail and head is the same). 
handle_call({dequeue, HeadPid}, _From, #state{
        head_pid = HeadPid,
        tail_pid = HeadPid} = State) ->
    io:format("Dequeue head pid == tail pid detected.~n", []),
    case dequeue_process(HeadPid) of
        ok ->
            NewQueueSize = 0,
            {reply, ok, State#state{
                queue_size = NewQueueSize,
                head_pid = undefined,
                tail_pid = undefined}};
        {error, timeout} ->
            {reply, {error, timeout}, State}
    end;

%% Match edge case when dequeing the head pid. 
handle_call({dequeue, HeadPid}, _From, #state{queue_size = QueueSize, head_pid = HeadPid} = State) ->
    RequestPid = self(),
    HeadPid ! {get_queue_process_state, RequestPid},
    receive 
        {ok, QueueProcessState} ->
            NewHeadPid = QueueProcessState#queue_process_state.back_pid,
            io:format("Dequeue head pid detected, new head is ~p.~n", [NewHeadPid]),
            case dequeue_process(HeadPid) of
                ok ->
                    NewQueueSize = QueueSize - 1,
                    {reply, ok, State#state{queue_size = NewQueueSize, head_pid = NewHeadPid}};
                {error, timeout} ->
                    {reply, {error, timeout}, State}
            end
    after
        2000 ->
            {reply, {error, timeout}, State}
    end;

handle_call(Call, _From, State) ->
    error_logger:error_report([{undefined_call, Call}]),
    {reply, ok, State}.

handle_cast(Cast, State) ->
    error_logger:error_report([{undefined_cast, Cast}]),
    {noreply, State}.

handle_info(Info, State) ->
    error_logger:error_report([{undefined_info, Info}]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

send_if_pid_valid(Pid, Message, WaitForAtom) when is_pid(Pid) ->
    Pid ! Message,
    receive
        WaitForAtom -> ok
    after
        2000 ->
            {error, timeout}
    end;

%% It is normal that the tail and head will have one pid undefined.
send_if_pid_valid(undefined, _Message, _WaitForAtom) ->
    ok.

dequeue_process(QueuePid) ->
    RequestPid = self(),
    QueuePid ! {dequeue, RequestPid},
    receive 
        {dequeued, QueueProcessState} ->
            ForwardPid = QueueProcessState#queue_process_state.forward_pid,
            BackPid = QueueProcessState#queue_process_state.back_pid,
            ok = send_if_pid_valid(
                ForwardPid,
                {set_back_pid, BackPid, RequestPid},
                set_back_pid_ok),
            ok = send_if_pid_valid(
                BackPid,
                {set_forward_pid, ForwardPid, RequestPid},
                set_forward_pid_ok),
            ok
    after
        2000 ->
            {error, timeout}
    end.

queue_process_loop(QueueProcessState) ->
    receive
        {dequeue, RequestPid} ->
            RequestPid ! {dequeued, QueueProcessState};
        chain ->
            io:format("~p.~n", [self()]),
            BackPid = QueueProcessState#queue_process_state.back_pid,
            case BackPid of
                undefined ->
                    io:format("Reached tail.~n", []);
                BackPid ->
                    BackPid ! chain
            end,
            ?MODULE:queue_process_loop(QueueProcessState);
        {get_queue_process_state, RequestPid} ->
            RequestPid ! {ok, QueueProcessState},
            ?MODULE:queue_process_loop(QueueProcessState);
        {set_forward_pid, ForwardPid, RequestPid} ->
            RequestPid ! set_forward_pid_ok,
            ?MODULE:queue_process_loop(QueueProcessState#queue_process_state{forward_pid = ForwardPid});
        {set_back_pid, BackPid, RequestPid} ->
            RequestPid ! set_back_pid_ok,
            ?MODULE:queue_process_loop(QueueProcessState#queue_process_state{back_pid = BackPid})
    after 
        60000 ->
            ?MODULE:queue_process_loop(QueueProcessState)
    end.

