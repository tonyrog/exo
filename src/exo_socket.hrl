%%% coding: latin-1
%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2016, Rogvall Invest AB, <tony@rogvall.se>
%%%
%%% This software is licensed as described in the file COPYRIGHT, which
%%% you should have received as part of this distribution. The terms
%%% are also available at http://www.rogvall.se/docs/copyright.txt.
%%%
%%% You may opt to use, copy, modify, merge, publish, distribute and/or sell
%%% copies of the Software, and permit persons to whom the Software is
%%% furnished to do so, under the terms of the COPYRIGHT file.
%%%
%%% This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
%%% KIND, either express or implied.
%%%
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2016, Tony Rogvall
%%% @doc
%%%    EXO socket definition
%%%
%%% Created : 15 Dec 2011 by Tony Rogvall
%%% @end

-ifndef(_EXO_SOCKET_HRL_).
-define(_EXO_SOCKET_HRL_, true).

-record(exo_socket,
	{
	  mdata,        %% data module  (e.g gen_tcp, ssl ...)
	  mctl,         %% control module  (e.g inet, ssl ...)
	  protocol=[],  %% [tcp|ssl|http] 
	  version,      %% Http version in use (1.0/keep-alive or 1.1)
	  transport,    %% ::port()  - transport socket
	  socket,       %% ::port() || Pid/Port/SSL/ etc
	  active=false, %% ::boolean() is active
	  mode=list,    %% :: list|binary 
	  packet=0,     %% packet mode
	  opts = [],    %% extra options
	  tags = {data,close,error},  %% data tags used
	  flow = undefined, %% Flow control policy, if any
	  mauth,        %% user-provided auth module - if any
	  auth_state,   %% state for user-provided auth module.
	  resource,     %% 
	  sockname      %% original sockname
	}).

-endif.
