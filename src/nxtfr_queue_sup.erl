%%%-------------------------------------------------------------------
%% @doc nxtfr_queue top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_queue_sup).
-author("christian@flodihn.se").
-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 0,
                 period => 1},

    NxtfrQueue = #{
        id => nxtfr_queue,
        start => {nxtfr_queue, start_link, [1000000]},
        type => worker},

    ChildSpecs = [NxtfrQueue],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
