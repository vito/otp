%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1996-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%
-module(supervisor_bridge_SUITE).
-export([all/1,starting/1,mini_terminate/1,mini_die/1,badstart/1]).
-export([client/1,init/1,internal_loop_init/1,terminate/2]).

-include("test_server.hrl").
-define(bridge_name,supervisor_bridge_SUITE_server).
-define(work_bridge_name,work_supervisor_bridge_SUITE_server).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

all(suite) -> [starting,mini_terminate,mini_die,badstart].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

starting(suite) -> [];
starting(Config) when is_list(Config) ->
    process_flag(trap_exit,true),

    ?line ignore = start(1),
    ?line {error,testing} = start(2),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mini_terminate(suite) -> [];
mini_terminate(Config) when is_list(Config) ->
    miniappl(1),
    ok.

mini_die(suite) -> [];
mini_die(Config) when is_list(Config) ->
    miniappl(2),
    ok.

miniappl(N) ->
    process_flag(trap_exit,true),
    ?line {ok,Server} = start(3),
    ?line Client = spawn_link(?MODULE,client,[N]),
    ?line Handle = test_server:timetrap(2000),
    ?line miniappl_loop(Client,Server),
    ?line test_server:timetrap_cancel(Handle).

miniappl_loop([],[]) ->
    ok;
miniappl_loop(Client,Server) ->
    io:format("Client ~p, Server ~p\n",[Client,Server]),
    receive
	{'EXIT',Client,_} ->
	    ?line miniappl_loop([],Server);
	{'EXIT',Server,killed} -> %% terminate
	    ?line miniappl_loop(Client,[]);
	{'EXIT',Server,died} -> %% die
	    ?line miniappl_loop(Client,[]);
	{dying,_Reason} ->
	    ?line miniappl_loop(Client, Server);
	Other ->
	    ?line exit({failed,Other})
    end.

%%%%%%%%%%%%%%%%%%%%
% Client

client(N) ->
    io:format("Client starting...\n"),
    ok = public_request(),
    case N of
	1 -> public_kill();
	2 -> ?work_bridge_name ! die
    end,
    io:format("Killed server, terminating client...\n"),
    exit(fine).

%%%%%%%%%%%%%%%%%%%%
% Non compliant server

start(N) ->
    supervisor_bridge:start_link({local,?bridge_name},?MODULE,N).

public_request() ->
    ?work_bridge_name ! {non_compliant_message,self()},
    io:format("Client waiting for answer...\n"),
    receive
	non_compliant_answer ->
	    ok
    end,
    io:format("Client got answer...\n").

public_kill() ->
    %% This func knows about supervisor_bridge
    exit(whereis(?work_bridge_name),kill).

init(1) ->
    ignore;
init(2) ->
    {error,testing};
init(3) ->
    %% This func knows about supervisor_bridge
    InternalPid = spawn_link(?MODULE,internal_loop_init,[self()]),
    receive
	{InternalPid,init_done} ->
	    {ok,InternalPid,self()}
    end.

internal_loop_init(Parent) ->
    register(?work_bridge_name, self()),
    Parent ! {self(),init_done},
    internal_loop({Parent,self()}).

internal_loop(State) ->
    receive
	{non_compliant_message,From} ->
	    io:format("Got request from ~p\n",[From]),
	    From ! non_compliant_answer,
	    internal_loop(State);
	die ->
	    exit(died)
    end.

terminate(Reason,{Parent,Worker}) ->
    %% This func knows about supervisor_bridge
    io:format("Terminating bridge...\n"),
    exit(kill,Worker),
    Parent ! {dying,Reason},
    anything.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

badstart(suite) -> [];
badstart(doc) -> "Test various bad ways of starting a supervisor bridge.";
badstart(Config) when is_list(Config) ->
    ?line Dog = test_server:timetrap(test_server:minutes(1)),

    %% Various bad arguments.

    ?line {'EXIT',_} =
	(catch supervisor_bridge:start_link({xxx,?bridge_name},?MODULE,1)),
    ?line {'EXIT',_} =
	(catch supervisor_bridge:start_link({local,"foo"},?MODULE,1)),
    ?line {'EXIT',_} =
	(catch supervisor_bridge:start_link(?bridge_name,?MODULE,1)),
    ?line [] = test_server:messages_get(),	% No messages waiting

    %% Already started.

    ?line process_flag(trap_exit, true),
    ?line {ok,Pid} =
	supervisor_bridge:start_link({local,?bridge_name},?MODULE,3),
    ?line {error,{already_started,Pid}} =
	supervisor_bridge:start_link({local,?bridge_name},?MODULE,3),
    ?line public_kill(),

    %% We used to wait 1 ms before retrieving the message queue,
    %% but that might not always be enough if the machine is overloaded.
    ?line receive
	      {'EXIT', Pid, killed} -> ok
	  end,
    ?line test_server:timetrap_cancel(Dog),
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
