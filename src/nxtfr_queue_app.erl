%%%-------------------------------------------------------------------
%% @doc nxtfr_queue public API
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_queue_app).
-author("christian@flodihn.se").
-behaviour(application).

-export([start/0, start/2, stop/1]).

start() ->
    application:start(sasl),
    application:start(nxtfr_event),
    application:start(nxtfr_autodiscovery),
    application:start(nxtfr_queue).

start(_StartType, _StartArgs) ->
    nxtfr_queue_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
