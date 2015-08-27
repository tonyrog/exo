%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2012 Feuerlabs, Inc. All rights reserved.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%%
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Marina Westman Lonne <malotte@malotte.net>
%%% @copyright (C) 2012, Feuerlabs, Inc. All rights reserved.
%%% @doc
%%%   Simple exo_http_server
%%% @end
%%% Created : 2010 by Tony Rogvall <tony@rogvall.se>

-module(exo_http_server).

-behaviour(exo_socket_server).

%% exo_socket_server callbacks
-export([init/2, 
	 data/3, 
	 close/2, 
	 error/3]).

-export([control/4]).

-include("log.hrl").
-include("exo_socket.hrl").
-include("exo_http.hrl").

-record(state,
	{
	  request,
	  response,
	  access = [],
	  request_handler
	}).

%% Configurable start
-export([start/2,
	 start_link/2,
	 response/5, response/6]).

%% For testing
-export([test/0]).
-export([handle_http_request/3]).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts a socket server on port Port with server options ServerOpts
%% that are sent to the server when a connection is established, 
%% i.e init is called.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec start(Port::integer(), 
	    ServerOptions::list({Option::atom(), Value::term()})) -> 
		   {ok, ChildPid::pid()} |
		   {error, Reason::term()}.

start(Port, Options) ->
    do_start(start, Port, Options).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts and links a socket server on port Port with server options ServerOpts
%% that are sent to the server when a connection is established, 
%% i.e init is called.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec start_link(Port::integer(), 
		 ServerOptions::list({Option::atom(), Value::term()})) -> 
			{ok, ChildPid::pid()} |
			{error, Reason::term()}.

start_link(Port, Options) ->
    do_start(start_link, Port, Options).


do_start(Start, Port, Options) ->
    ?debug("exo_http_server: ~w: port ~p, server options ~p",
	   [Start, Port, Options]),
    {ServerOptions,Options1} = opts_take([request_handler,access],Options),
    Dir = code:priv_dir(exo),
    exo_socket_server:Start(Port, [tcp,probe_ssl,http],
			    [{active,once},{reuseaddr,true},
			     {verify, verify_none},
			     {keyfile, filename:join(Dir, "host.key")},
			     {certfile, filename:join(Dir, "host.cert")} |
			     Options1],
			    ?MODULE, ServerOptions).

%%-----------------------------------------------------------------------------
%% @doc
%%  Init function called when a connection is established.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec init(Socket::#exo_socket{}, 
	   ServerOptions::list({Option::atom(), Value::term()})) -> 
		  {ok, State::#state{}}.

init(Socket, Options) ->
    {ok,{_IP,_Port}} = exo_socket:peername(Socket),
    ?debug("exo_http_server: connection from: ~p : ~p,\n options ~p",
	   [_IP, _Port, Options]),
    Access = proplists:get_value(access, Options, []),
    Module = proplists:get_value(request_handler, Options, undefined),
    {ok, #state{ access = Access, request_handler = Module}}.    


%% To avoid a compiler warning. Should we actually support something here?
%%-----------------------------------------------------------------------------
%% @doc
%%  Control function - not used.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec control(Socket::#exo_socket{}, 
	      Request::term(), From::term(), State::#state{}) -> 
		     {ignore, State::#state{}}.

control(_Socket, _Request, _From, State) ->
    {ignore, State}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Data function called when data is received.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec data(Socket::#exo_socket{}, 
	   Data::term(),
	   State::#state{}) -> 
		  {ok, NewState::#state{}} |
		  {stop, {error, Reason::term()}, NewState::#state{}}.

data(Socket, Data, State) ->
    ?debug("exo_http_server:~w: data = ~w\n", [self(),Data]),
    case Data of
	{http_request, Method, Uri, Version} ->
	    CUri = exo_http:convert_uri(Uri),
	    Req  = #http_request { method=Method,uri=CUri,version=Version},
	    case exo_http:recv_headers(Socket, Req) of
		{ok, Req1} ->
		    handle_request(Socket, Req1, State);
		Error ->
		    {stop, Error, State}
	    end;
	{http_error, ?CRNL} -> 
	    {ok, State};
	{http_error, ?NL} ->
	    {ok, State};
	_ when is_list(Data); is_binary(Data) ->
	    ?debug("exo_http_server: request data: ~p\n", [Data]),
	    {stop, {error,sync_error}, State};
	Error ->
	    {stop, Error, State}
    end.

%%-----------------------------------------------------------------------------
%% @doc
%%  Close function called when a connection is closed.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec close(Socket::#exo_socket{}, 
	    State::#state{}) -> 
		   {ok, NewState::#state{}}.

close(_Socket, State) ->
    ?debug("exo_http_server: close\n", []),
    {ok,State}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Error function called when an error is detected.
%%  Stops the server.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec error(Socket::#exo_socket{},
	    Error::term(),
	    State::#state{}) -> 
		   {stop, {error, Reason::term()}, NewState::#state{}}.

error(_Socket,Error,State) ->
    ?debug("exo_http_serber: error = ~p\n", [Error]),
    {stop, Error, State}.    


handle_request(Socket, R, State) ->
    ?debug("exo_http_server: request = ~s\n", 
	 [[exo_http:format_request(R),?CRNL,
	   exo_http:format_hdr(R#http_request.headers),
	   ?CRNL]]),
    case exo_http:recv_body(Socket, R) of
	{ok, Body} ->
	    handle_body(Socket, R, Body, State);
	{error, closed} ->
	    {stop, normal,State};
	Error ->
	    {stop, Error, State}
    end.
	    
handle_body(Socket, Request, Body, State) ->
    RH = State#state.request_handler,
    {M, F, As} = request_handler(RH,Socket, Request, Body),
    ?debug("exo_http_server: calling ~p with -BODY:\n~s\n-END-BODY\n", 
	   [RH, Body]),
    case apply(M, F, As) of
	ok -> {ok, State};
	stop -> {stop, normal, State};
	{error, Error} ->  {stop, Error, State}
    end.

%% @private
request_handler(undefined, Socket, Request, Body) ->
    {?MODULE, handle_http_request, [Socket, Request, Body]};
request_handler(Module, Socket, Request, Body) when is_atom(Module) ->
    {Module, handle_http_request, [Socket, Request, Body]};
request_handler({Module, Function}, Socket, Request, Body) ->
    {Module, Function, [Socket, Request, Body]};
request_handler({Module, Function, XArgs}, Socket, Request, Body) ->
    {Module, Function, [Socket, Request, Body | XArgs]}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Support function for sending an http response.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec response(Socket::#exo_socket{}, 
	      Connection::string() | undefined,
	      Status::integer(),
	      Phrase::string(),
	      Body::string()) -> 
				ok |
				{error, Reason::term()}.

response(S, Connection, Status, Phrase, Body) ->
    response(S, Connection, Status, Phrase, Body, []).

%%-----------------------------------------------------------------------------
%% @doc
%%  Support function for sending an http response.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec response(Socket::#exo_socket{}, 
	      Connection::string() | undefined,
	      Status::integer(),
	      Phrase::string(),
	      Body::string(),
	      Opts::list()) -> 
				ok |
				{error, Reason::term()}.
response(S, Connection, Status, Phrase, Body, Opts) ->
    {Content_type, Opts1} = opt_take(content_type, Opts, "text/plain"),
    {Set_cookie, Opts2} = opt_take(set_cookie, Opts1, undefined),
    {Transfer_encoding,Opts3} = opt_take(transfer_encoding, Opts2, undefined),
    {Location,Opts4} = opt_take(location, Opts3, undefined),
    ContentLength = if Transfer_encoding =:= "chunked", Body == "" ->
			    undefined;
		       true ->
			    content_length(Body)
		    end,
    H = #http_shdr { connection = Connection,
		     content_length = ContentLength,
		     content_type = Content_type,
		     set_cookie = Set_cookie,
		     transfer_encoding = Transfer_encoding,
		     location = Location,
		     other = Opts4 },
		     
    R = #http_response { version = {1, 1},
			 status = Status,
			 phrase = Phrase,
			 headers = H },
    Response = [exo_http:format_response(R),
		?CRNL,
		exo_http:format_hdr(H),
		?CRNL,
		Body],
    ?debug("exo_http_server: response:\n~s\n", [Response]),
    exo_socket:send(S, Response).

content_length(B) when is_binary(B) ->
    byte_size(B);
content_length(L) when is_list(L) ->
    iolist_size(L).

%% return value or defaule and the option list without the key
opt_take(K, L, Def) ->
    case lists:keytake(K, 1, L) of
	{value,{_,V},L1} -> {V,L1};
	false -> {Def,L}
    end.

%% return a option list of value from Ks remove the keys found
opts_take(Ks, L) ->
    opts_take_(Ks, L, []).

opts_take_([K|Ks], L, Acc) ->
    case lists:keytake(K, 1, L) of
	{value,Kv,L1} ->
	    opts_take_(Ks, L1, [Kv|Acc]);
	false ->
	    opts_take_(Ks, L, Acc)
    end;
opts_take_([], L, Acc) ->
    {lists:reverse(Acc), L}.

%% @private
handle_http_request(Socket, Request, Body) ->
    Url = Request#http_request.uri,
    ?debug("exo_http_server: -BODY:\n~s\n-END-BODY\n", [Body]),
    if Request#http_request.method =:= 'GET',
       Url#url.path =:= "/quit" ->
	    response(Socket, "close", 200, "OK", "QUIT"),
	    exo_socket:shutdown(Socket, write),
	    stop;
       Url#url.path =:= "/test" ->
	    response(Socket, undefined, 200, "OK", "OK"),
	    ok;
       true ->
	    response(Socket, undefined, 404, "Not Found", 
		     "Object not found"),
	    ok
    end.

test() ->
    Dir = code:priv_dir(exo),
    exo_socket_server:start(9000, [tcp,probe_ssl,http],
			    [{active,once},{reuseaddr,true},
			     {verify, verify_none},
			     {keyfile, filename:join(Dir, "host.key")},
			     {certfile, filename:join(Dir, "host.cert")}],
			    ?MODULE, []).
