%%%-------------------------------------------------------------------
%% @doc nxtfr_queue public API
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_queue_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    nxtfr_queue_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
