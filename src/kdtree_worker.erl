-module(kdtree_worker).

-behavior(gen_server).

-record(node, {
          location,
          left,
          right
         }).

% greater than max distance between two points on earth
-define(MAXDISTANCE, 13000).
% in miles
-define(EARTHRADIUS, 3961).

-export([build/1, nearest/1, nearby/2]).
-export([init/1, start_link/0, handle_cast/2, handle_call/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, []}.

% clienside functions
-spec build(list()) -> #node{}.
build(CoordinateList) ->
    gen_server:call(?MODULE, {build, CoordinateList}).

-spec nearest(tuple()) -> tuple().
nearest(Coordinate) ->
    gen_server:call(?MODULE, {nearest, Coordinate}).

-spec nearby(tuple(), non_neg_integer()) -> tuple().
nearby(Coordinate, Range) ->
    gen_server:call(?MODULE, {nearby, Coordinate, Range}).

% callback functions
handle_call(Msg, _From, State) ->
    case Msg of
        {build, List} ->
            Tree = build(List, 0),
            {reply, Tree, Tree};
        {nearest, Coordinate} ->
            Nearest = nearest(State, Coordinate),
            {reply, Nearest, State};
        {nearby, Coordinate, Range} ->
            Nearby = nearby(State, Coordinate, Range),
            {reply, Nearby, State}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

% private functions
-spec build(list(), non_neg_integer()) -> undefined | #node{}.
build(CoordinateList, _Depth) when length(CoordinateList) == 0 ->
    undefined;
build(CoordinateList, Depth) when length(CoordinateList) == 1 ->
    #node{
       location=hd(CoordinateList),
       left=build([], Depth + 1),
       right=build([], Depth + 1)
      };
build(CoordinateList, Depth) ->
    K = tuple_size(lists:nth(1, CoordinateList)),
    Axis = Depth rem K,
    SortedCoordinateList = case Axis of
                               0 -> lists:keysort(1, CoordinateList);
                               1 -> lists:keysort(2, CoordinateList)
                           end,
    Median = (length(SortedCoordinateList) div 2) + 1,
    #node{
       location= lists:nth(Median, SortedCoordinateList),
       left=build(lists:sublist(SortedCoordinateList, 1, Median - 1), Depth + 1),
       right=build(lists:sublist(SortedCoordinateList, Median + 1, length(SortedCoordinateList)), Depth + 1)
       }.

-spec nearest(#node{} | undefined, tuple()) -> undefined | tuple().
nearest(undefined, _Coordinate) ->
    undefined;
nearest(Node, Coordinate) ->
    nearest(Node, Coordinate, Node#node.location, ?MAXDISTANCE, 0).

-spec nearest(#node{}, tuple(), tuple(), non_neg_integer(), non_neg_integer()) -> undefined | tuple().
nearest(undefined, _Coordinate, Closest, MinDist, _Depth) ->
    {Closest, MinDist};
nearest(Node, Coordinate, Closest, MinDist, Depth) ->
    Axis = get_axis(Depth, Coordinate),
    Distance = haversine_distance(Coordinate, Node#node.location),
    {NewClosest, NewMinDist} = case Distance < MinDist andalso Coordinate /= Node#node.location of
                                   true ->
                                       {Node#node.location, Distance};
                                   false ->
                                       {Closest, MinDist}
                               end,
    NodeDim = get_dimension(Axis, Node#node.location),
    PointDim = get_dimension(Axis, Coordinate),
    case {PointDim > NodeDim, Node#node.left, Node#node.right} of
        {_, undefined, undefined} ->
            {NewClosest, NewMinDist};
        {true, undefined, Right} ->
            nearest(Right, Coordinate, NewClosest, NewMinDist, Depth + 1);
        {true, Left, Right} ->
            {NewerClosest, NewerMinDist} = nearest(Left, Coordinate, NewClosest, NewMinDist, Depth + 1),
            case (PointDim + MinDist) >= NodeDim of
                true -> nearest(Right, Coordinate, NewerClosest, NewerMinDist, Depth + 1);
                false -> {NewerClosest, NewerMinDist}
            end;
        {false, Left, undefined} ->
            nearest(Left, Coordinate, NewClosest, NewMinDist, Depth + 1);
        {false, Left, Right} ->
            {NewerClosest, NewerMinDist} = nearest(Right, Coordinate, NewClosest, NewMinDist, Depth + 1),
            case (PointDim - MinDist) =< NodeDim of
                true -> nearest(Left, Coordinate, NewClosest, NewMinDist, Depth + 1);
                false -> {NewerClosest, NewerMinDist}
            end
    end.

-spec nearby(#node{} | undefined, tuple(), tuple()) -> undefined | list().
nearby(undefined, _Coordinate, _Range) ->
    undefined;
nearby(Node, Coordinate, Range) ->
    nearby(Node, Coordinate, Node#node.location, Range, 0, []).

-spec nearby(#node{} | undefined, tuple(), tuple(), non_neg_integer(), non_neg_integer(), list()) -> undefined | list().
nearby(undefined, _Coordinate, _NearbyCoordinate, _Range, _Depth, List) ->
    List;
nearby(Node, Coordinate, NearbyCoordinate, Range, Depth, List) ->
    Distance = haversine_distance(Coordinate, Node#node.location),
    NewList = case Distance < Range andalso Coordinate /= Node#node.location of
                  true ->
                      List ++ [Node#node.location];
                  false ->
                      List
              end,

    nearby(Node#node.left, Coordinate, NearbyCoordinate, Range, Depth + 1, NewList) ++
        (nearby(Node#node.right, Coordinate, NearbyCoordinate, Range, Depth + 1, NewList) -- NewList).

-spec get_dimension(1 | 2, tuple()) -> float().
get_dimension(Axis, Coordinate) ->
    lists:nth(Axis, tuple_to_list(Coordinate)).

-spec haversine_distance(tuple(), tuple()) -> float().
haversine_distance({Lat1, Long1}, {Lat2, Long2}) ->
    V = math:pi()/180,
    DeltaLat = (Lat2 - Lat1) * V,
    DeltaLong = (Long2 - Long1) * V,
    A = math:pow(math:sin(DeltaLat/2), 2) + math:cos(Lat1 * V) * math:cos(Lat2 * V) * math:pow(math:sin(DeltaLong/2), 2),
    C = 2 * math:atan2(math:sqrt(A), math:sqrt(1-A)),
    ?EARTHRADIUS * C.

-spec get_axis(non_neg_integer(), tuple()) -> 1 | 2.
get_axis(Depth, Coordinate) ->
    case Depth rem tuple_size(Coordinate) of
        0 -> 1;
        1 -> 2
    end.