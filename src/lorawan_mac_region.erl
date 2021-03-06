%
% Copyright (c) 2016-2018 Petr Gotthard <petr.gotthard@centrum.cz>
% All rights reserved.
% Distributed under the terms of the MIT License. See the LICENSE file.
%
-module(lorawan_mac_region).

-export([freq_range/1, datar_to_dr/2]).
-export([join1_window/2, join2_window/3, rx1_window/3, rx2_window/3, rx2_rf/2]).
-export([max_uplink_snr/1, max_uplink_snr/2, max_downlink_snr/3]).
-export([set_channels/3]).
-export([tx_time/2, tx_time/3]).

-include("lorawan_db.hrl").

% receive windows

join1_window(#network{region=Region, join1_delay=Delay}, RxQ) ->
    tx_window(RxQ#rxq.tmst, Delay, rx1_rf(Region, RxQ, 0)).

join2_window(#network{join2_delay=Delay}=Network, Node, RxQ) ->
    tx_window(RxQ#rxq.tmst, Delay, rx2_rf(Network, Node)).

rx1_window(#network{region=Region, rx1_delay=Delay},
        #node{rxwin_use={Offset, _, _}}, RxQ) ->
    tx_window(RxQ#rxq.tmst, Delay, rx1_rf(Region, RxQ, Offset)).

rx2_window(#network{rx2_delay=Delay}=Network, Node, RxQ) ->
    tx_window(RxQ#rxq.tmst, Delay, rx2_rf(Network, Node)).

% we calculate in fixed-point numbers
rx1_rf(<<"US902">> = Region, RxQ, Offset) ->
    RxCh = f2ch(RxQ#rxq.freq, {9023, 2}, {9030, 16}),
    tx_offset(Region, RxQ, ch2f(Region, RxCh rem 8), Offset);
rx1_rf(<<"US902-PR">> = Region, RxQ, Offset) ->
    RxCh = f2ch(RxQ#rxq.freq, {9023, 2}, {9030, 16}),
    tx_offset(Region, RxQ, ch2f(Region, RxCh div 8), Offset);
rx1_rf(<<"AU915">> = Region, RxQ, Offset) ->
    RxCh = f2ch(RxQ#rxq.freq, {9152, 2}, {9159, 16}),
    tx_offset(Region, RxQ, ch2f(Region, RxCh rem 8), Offset);
rx1_rf(<<"CN470">> = Region, RxQ, Offset) ->
    RxCh = f2ch(RxQ#rxq.freq, {4703, 2}),
    tx_offset(Region, RxQ, ch2f(Region, RxCh rem 48), Offset);
rx1_rf(Region, RxQ, Offset) ->
    tx_offset(Region, RxQ, RxQ#rxq.freq, Offset).

rx2_rf(#network{region=Region, tx_codr=CodingRate}, #node{rxwin_use={_, DataRate, Freq}}) ->
    #txq{freq=Freq, datr=dr_to_datar(Region, DataRate), codr=CodingRate};
rx2_rf(#network{region=Region, tx_codr=CodingRate}, #profile{rxwin_set={_, DataRate, Freq}}) ->
    #txq{freq=Freq, datr=dr_to_datar(Region, DataRate), codr=CodingRate}.

f2ch(Freq, {Start, Inc}) -> round(10*Freq-Start) div Inc.

% the channels are overlapping, return the integer value
f2ch(Freq, {Start1, Inc1}, _) when round(10*Freq-Start1) rem Inc1 == 0 ->
    round(10*Freq-Start1) div Inc1;
f2ch(Freq, _, {Start2, Inc2}) when round(10*Freq-Start2) rem Inc2 == 0 ->
    64 + round(10*Freq-Start2) div Inc2.

ch2f(<<"EU868">>, Ch) ->
    if
        Ch >= 0, Ch =< 2 ->
            ch2fi(Ch, {8681, 2});
        Ch >= 3, Ch =< 7 ->
            ch2fi(Ch, {8671, 2});
        Ch == 8 ->
            868.8
    end;
ch2f(<<"CN779">>, Ch) ->
    ch2fi(Ch, {7795, 2});
ch2f(<<"EU433">>, Ch) ->
    ch2fi(Ch, {4331.75, 2});
ch2f(Region, Ch)
        when Region == <<"US902">>; Region == <<"US902-PR">>; Region == <<"AU915">> ->
    ch2fi(Ch, {9233, 6});
ch2f(<<"CN470">>, Ch) ->
    ch2fi(Ch, {5003, 2}).

ch2fi(Ch, {Start, Inc}) -> (Ch*Inc + Start)/10.

tx_offset(Region, RxQ, Freq, Offset) ->
    DataRate = datar_to_down(Region, RxQ#rxq.datr, Offset),
    #txq{freq=Freq, datr=DataRate, codr=RxQ#rxq.codr}.

tx_window(Recvd, Delay, TxQ) ->
    TxQ#txq{tmst=Recvd+Delay*1000000}.

datar_to_down(Region, DataRate, Offset) ->
    DR2 = dr_to_down(Region, datar_to_dr(Region, DataRate), Offset),
    dr_to_datar(Region, DR2).

dr_to_down(<<"AS923">>, DR, Offset) ->
    % TODO: should be derived based on DownlinkDwellTime
    MinDR = 0,
    EffOffset =
        if
            Offset > 5 -> 5 - Offset;
            true -> Offset
        end,
    min(5, max(MinDR, DR-EffOffset));
dr_to_down(Region, DR, Offset) ->
    lists:nth(Offset+1, drs_to_down(Region, DR)).

drs_to_down(Region, DR)
        when Region == <<"US902">>; Region == <<"US902-PR">> ->
    case DR of
        0 -> [10, 9,  8,  8];
        1 -> [11, 10, 9,  8];
        2 -> [12, 11, 10, 9];
        3 -> [13, 12, 11, 10];
        4 -> [13, 13, 12, 11]
    end;
drs_to_down(Region, DR)
        when Region == <<"AU915">> ->
    case DR of
        0 -> [8,  8,  8,  8,  8,  8];
        1 -> [9,  8,  8,  8,  8,  8];
        2 -> [10, 9,  8,  8,  8,  8];
        3 -> [11, 10, 9,  8,  8,  8];
        4 -> [12, 11, 10, 9,  8,  8];
        5 -> [13, 12, 11, 10, 9,  8];
        6 -> [13, 13, 12, 11, 10, 9]
    end;
drs_to_down(_Region, DR) ->
    case DR of
        0 -> [0, 0, 0, 0, 0, 0];
        1 -> [1, 0, 0, 0, 0, 0];
        2 -> [2, 1, 0, 0, 0, 0];
        3 -> [3, 2, 1, 0, 0, 0];
        4 -> [4, 3, 2, 1, 0, 0];
        5 -> [5, 4, 3, 2, 1, 0];
        6 -> [6, 5, 4, 3, 2, 1];
        7 -> [7, 6, 5, 4, 3, 2]
    end.

% data rate and end-device output power encoding

datars(Region)
        when Region == <<"US902">>; Region == <<"US902-PR">> -> [
    {0,  {10, 125}},
    {1,  {9, 125}},
    {2,  {8, 125}},
    {3,  {7, 125}},
    {4,  {8, 500}}
    | us_down_datars()];
datars(Region)
        when Region == <<"AU915">> -> [
    {0,  {12, 125}},
    {1,  {11, 125}},
    {2,  {10, 125}},
    {3,  {9, 125}},
    {4,  {8, 125}},
    {5,  {7, 125}},
    {6,  {8, 500}}
    | us_down_datars()];
datars(_Region) -> [
    {0, {12, 125}},
    {1, {11, 125}},
    {2, {10, 125}},
    {3, {9, 125}},
    {4, {8, 125}},
    {5, {7, 125}},
    {6, {7, 250}},
    {7, 50000}]. % FSK

us_down_datars() -> [
    {8,  {12, 500}},
    {9,  {11, 500}},
    {10, {10, 500}},
    {11, {9, 500}},
    {12, {8, 500}},
    {13, {7, 500}}].

dr_to_tuple(Region, DR) ->
    case lists:keyfind(DR, 1, datars(Region)) of
        {_, DataRate} -> DataRate;
        false -> undefined
    end.

dr_to_datar(Region, DR) ->
    tuple_to_datar(dr_to_tuple(Region, DR)).

datar_to_dr(Region, DataRate) ->
    case lists:keyfind(datar_to_tuple(DataRate), 2, datars(Region)) of
        {DR, _} -> DR;
        false -> undefined
    end.

tuple_to_datar({SF, BW}) ->
    <<"SF", (integer_to_binary(SF))/binary, "BW", (integer_to_binary(BW))/binary>>;
tuple_to_datar(DataRate) ->
    DataRate. % FSK

datar_to_tuple(DataRate) when is_binary(DataRate) ->
    [SF, BW] = binary:split(DataRate, [<<"SF">>, <<"BW">>], [global, trim_all]),
    {binary_to_integer(SF), binary_to_integer(BW)};
datar_to_tuple(DataRate) when is_integer(DataRate) ->
    DataRate. % FSK

codr_to_tuple(CodingRate) ->
    [A, B] = binary:split(CodingRate, [<<"/">>], [global, trim_all]),
    {binary_to_integer(A), binary_to_integer(B)}.

% {Min, Max}
freq_range(<<"EU868">>) -> {863, 870};
freq_range(<<"US902">>) -> {902, 928};
freq_range(<<"US902-PR">>) -> {902, 928};
freq_range(<<"CN779">>) -> {779, 787};
freq_range(<<"EU433">>) -> {433, 435};
freq_range(<<"AU915">>) -> {915, 928};
freq_range(<<"CN470">>) -> {470, 510};
freq_range(<<"AS923">>) -> {915, 928};
freq_range(<<"KR920">>) -> {920, 923};
freq_range(<<"IN925">>) -> {865, 867}.

max_uplink_snr(DataRate) ->
    {SF, _} = datar_to_tuple(DataRate),
    max_snr(SF).

max_uplink_snr(Region, DataRate) ->
    {SF, _} = dr_to_tuple(Region, DataRate),
    max_snr(SF).

max_downlink_snr(Region, DataRate, Offset) ->
    {SF, _} = dr_to_tuple(Region, dr_to_down(Region, DataRate, Offset)),
    max_snr(SF).

% from SX1272 DataSheet, Table 13
max_snr(SF) ->
    -5-2.5*(SF-6). % dB

% link_adr_req command

set_channels(Region, {TXPower, DataRate, Chans}, FOptsOut)
        when Region == <<"US902">>; Region == <<"US902-PR">>; Region == <<"AU915">> ->
    case all_bit({0,63}, Chans) of
        true ->
            [{link_adr_req, DataRate, TXPower, build_bin(Chans, {64, 71}), 6, 0} | FOptsOut];
        false ->
            [{link_adr_req, DataRate, TXPower, build_bin(Chans, {64, 71}), 7, 0} |
                append_mask(3, {TXPower, DataRate, Chans}, FOptsOut)]
    end;
set_channels(Region, {TXPower, DataRate, Chans}, FOptsOut)
        when Region == <<"CN470">> ->
    case all_bit({0,95}, Chans) of
        true ->
            [{link_adr_req, DataRate, TXPower, 0, 6, 0} | FOptsOut];
        false ->
            append_mask(5, {TXPower, DataRate, Chans}, FOptsOut)
    end;
set_channels(_Region, {TXPower, DataRate, Chans}, FOptsOut) ->
    [{link_adr_req, DataRate, TXPower, build_bin(Chans, {0, 15}), 0, 0} | FOptsOut].

some_bit(MinMax, Chans) ->
    lists:any(
        fun(Tuple) -> match_part(MinMax, Tuple) end, Chans).

all_bit(MinMax, Chans) ->
    lists:any(
        fun(Tuple) -> match_whole(MinMax, Tuple) end, Chans).

none_bit(MinMax, Chans) ->
    lists:all(
        fun(Tuple) -> not match_part(MinMax, Tuple) end, Chans).

match_part(MinMax, {A,B}) when B < A ->
    match_part(MinMax, {B,A});
match_part({Min, Max}, {A,B}) ->
    (A =< Max) and (B >= Min).

match_whole(MinMax, {A,B}) when B < A ->
    match_whole(MinMax, {B,A});
match_whole({Min, Max}, {A,B}) ->
    (A =< Min) and (B >= Max).

build_bin(Chans, {Min, Max}) ->
    Bits = Max-Min+1,
    lists:foldl(
        fun(Tuple, Acc) ->
            <<Num:Bits>> = build_bin0({Min, Max}, Tuple),
            Num bor Acc
        end, 0, Chans).

build_bin0(MinMax, {A, B}) when B < A ->
    build_bin0(MinMax, {B, A});
build_bin0({Min, Max}, {A, B}) when B < Min; Max < A ->
    % out of range
    <<0:(Max-Min+1)>>;
build_bin0({Min, Max}, {A, B}) ->
    C = max(Min, A),
    D = min(Max, B),
    Bits = Max-Min+1,
    % construct the binary
    Bin = <<-1:(D-C+1), 0:(C-Min)>>,
    case bit_size(Bin) rem Bits of
        0 -> Bin;
        N -> <<0:(Bits-N), Bin/bits>>
    end.

append_mask(Idx, _, FOptsOut) when Idx < 0 ->
    FOptsOut;
append_mask(Idx, {TXPower, DataRate, Chans}, FOptsOut) ->
    append_mask(Idx-1, {TXPower, DataRate, Chans},
        case build_bin(Chans, {16*Idx, 16*(Idx+1)-1}) of
            0 -> FOptsOut;
            ChMask -> [{link_adr_req, DataRate, TXPower, ChMask, Idx, 0} | FOptsOut]
        end).

% transmission time estimation

tx_time(FOpts, FRMPayloadSize, TxQ) ->
    tx_time(phy_payload_size(FOpts, FRMPayloadSize), TxQ).

phy_payload_size(FOpts, FRMPayloadSize) ->
    1+7+byte_size(FOpts)+1+FRMPayloadSize+4.

tx_time(PhyPayloadSize, #txq{datr=DataRate, codr=CodingRate}) ->
    {SF, BW} = datar_to_tuple(DataRate),
    {4, CR} = codr_to_tuple(CodingRate),
    tx_time(PhyPayloadSize, SF, CR, BW*1000).

% see http://www.semtech.com/images/datasheet/LoraDesignGuide_STD.pdf
tx_time(PL, SF, CR, 125000) when SF == 11; SF == 12 ->
    % Optimization is mandated with spreading factors of 11 and 12 at 125 kHz bandwidth
    tx_time(PL, SF, CR, 125000, 1);
tx_time(PL, SF, CR, 250000) when SF == 12 ->
    % The firmware uses also optimization for SF 12 at 250 kHz bandwidth
    tx_time(PL, SF, CR, 250000, 1);
tx_time(PL, SF, CR, BW) ->
    tx_time(PL, SF, CR, BW, 0).

tx_time(PL, SF, CR, BW, DE) ->
    TSym = math:pow(2, SF)/BW,
    % lorawan uses an explicit header
    PayloadSymbNb = 8 + max(ceiling((8*PL-4*SF+28+16)/(4*(SF-2*DE)))*CR, 0),
    % lorawan uses 8 symbols preamble
    % the last +1 is a correction based on practical experiments
    1000*((8 + 4.25) + PayloadSymbNb + 1)*TSym.

ceiling(X) ->
    T = erlang:trunc(X),
    case (X - T) of
        Neg when Neg < 0 -> T;
        Pos when Pos > 0 -> T + 1;
        _ -> T
    end.

-include_lib("eunit/include/eunit.hrl").

region_test_()-> [
    ?_assertEqual({12,125}, datar_to_tuple(<<"SF12BW125">>)),
    ?_assertEqual({4,6}, codr_to_tuple(<<"4/6">>)),
    % values [ms] verified using the LoRa Calculator, +1 chirp correction based on experiments
    ?_assertEqual(1024, test_tx_time(<<"0123456789">>, <<"SF12BW125">>, <<"4/5">>)),
    ?_assertEqual(297, test_tx_time(<<"0123456789">>, <<"SF10BW125">>, <<"4/5">>)),
    ?_assertEqual(21, test_tx_time(<<"0123456789">>, <<"SF7BW250">>, <<"4/5">>)),
    ?_assertEqual(11, test_tx_time(<<"0123456789">>, <<"SF7BW500">>, <<"4/5">>)),
    ?_assertEqual(dr_to_datar(<<"EU868">>, 0), <<"SF12BW125">>),
    ?_assertEqual(dr_to_datar(<<"US902">>, 8), <<"SF12BW500">>),
    ?_assertEqual(datar_to_dr(<<"EU868">>, <<"SF9BW125">>), 3),
    ?_assertEqual(datar_to_dr(<<"US902">>, <<"SF7BW500">>), 13),
    ?_assertEqual(<<"SF10BW500">>, datar_to_down(<<"US902">>, <<"SF10BW125">>, 0))].

test_tx_time(Packet, DataRate, CodingRate) ->
    round(tx_time(byte_size(Packet),
        % the constants are only to make Dialyzer happy
        #txq{freq=869.525, datr=DataRate, codr=CodingRate})).

bits_test_()-> [
    ?_assertEqual(7, build_bin([{0,2}], {0,15})),
    ?_assertEqual(0, build_bin([{0,2}], {16,31})),
    ?_assertEqual(65535, build_bin([{0,71}], {0,15})),
    ?_assertEqual(true, some_bit({0, 71}, [{0,71}])),
    ?_assertEqual(true, all_bit({0, 71}, [{0,71}])),
    ?_assertEqual(false, none_bit({0, 71}, [{0,71}])),
    ?_assertEqual(true, some_bit({0, 15}, [{0,2}])),
    ?_assertEqual(false, all_bit({0, 15}, [{0,2}])),
    ?_assertEqual(false, none_bit({0, 15}, [{0,2}])),
    ?_assertEqual([{link_adr_req,<<"SF12BW250">>,14,7,0,0}],
        set_channels(<<"EU868">>, {14, <<"SF12BW250">>, [{0, 2}]}, [])),
    ?_assertEqual([{link_adr_req,<<"SF12BW500">>,20,0,7,0}, {link_adr_req,<<"SF12BW500">>,20,255,0,0}],
        set_channels(<<"US902">>, {20, <<"SF12BW500">>, [{0, 7}]}, [])),
    ?_assertEqual([{link_adr_req,<<"SF12BW500">>,20,2,7,0}, {link_adr_req,<<"SF12BW500">>,20,65280,0,0}],
        set_channels(<<"US902">>, {20, <<"SF12BW500">>, [{8, 15}, {65, 65}]}, []))
].

% end of file
