
#
# Public API
#

Client(host::String, port::Int) = Client(URI("mongodb://$host:$port"))
Client(uri::String) = Client(URI(uri))
Client() = Client("localhost", 27017)

function Collection(database::Database, coll_name::String)
    coll_handle = mongoc_database_get_collection(database.handle, coll_name)
    if coll_handle == C_NULL
        error("Failed creating collection $coll_name on db $(database.name).")
    end
    return Collection(database, coll_name, coll_handle)
end

function Collection(client::Client, db_name::String, coll_name::String)
    database = Database(client, db_name)
    return Collection(database, coll_name)
end

"""
    set_appname!(client::Client, appname::String)

Sets the application name for this client.

This string, along with other internal driver details,
is sent to the server as part of the initial connection handshake.

# C API

* [`mongoc_client_set_appname`](http://mongoc.org/libmongoc/current/mongoc_client_set_appname.html).
"""
function set_appname!(client::Client, appname::String)
    ok = mongoc_client_set_appname(client.handle, appname)
    if !ok
        error("Couldn't set appname=$appname for client $client.")
    end
    nothing
end

"""
    command_simple(database::Database, command::Union{String, BSON}) :: BSON

Executes a `command` given by a JSON string or a BSON instance.

It returns the first document from the result cursor.

# Example

```julia
julia> client = Mongoc.Client() # connects to localhost at port 27017
Client(URI("mongodb://localhost:27017"))

julia> bson_result = Mongoc.command_simple(client[\"admin\"], "{ \"ping\" : 1 }")
BSON("{ "ok" : 1.0 }")
```

# C API

* [`mongoc_database_command_simple`](http://mongoc.org/libmongoc/current/mongoc_database_command_simple.html)

"""
function command_simple(database::Database, command::BSON) :: BSON
    reply = BSON()
    err = BSONError()
    ok = mongoc_database_command_simple(database.handle, command.handle, C_NULL, reply.handle, err)
    if !ok
        error("$err.")
    end
    return reply
end

function command_simple(collection::Collection, command::BSON) :: BSON
    reply = BSON()
    err = BSONError()
    ok = mongoc_collection_command_simple(collection.handle, command.handle, C_NULL, reply.handle, err)
    if !ok
        error("$err.")
    end
    return reply
end

function ping(client::Client) :: BSON
    return command_simple(client["admin"], BSON("""{ "ping" : 1 }"""))
end

function find_databases(client::Client; options::Union{Nothing, BSON}=nothing) :: Cursor
    options_handle = options == nothing ? C_NULL : options.handle
    cursor_handle = mongoc_client_find_databases_with_opts(client.handle, options_handle)
    if cursor_handle == C_NULL
        error("Couldn't execute query.")
    end
    return Cursor(cursor_handle)
end

function get_database_names(client::Client; options::Union{Nothing, BSON}=nothing) :: Vector{String}
    result = Vector{String}()
    for bson_database in find_databases(client, options=options)
        push!(result, bson_database["name"])
    end
    return result
end

function find_collections(database::Database; options::Union{Nothing, BSON}=nothing) :: Cursor
    options_handle = options == nothing ? C_NULL : options.handle
    cursor_handle = mongoc_database_find_collections_with_opts(database.handle, options_handle)
    if cursor_handle == C_NULL
        error("Couldn't execute query.")
    end
    return Cursor(cursor_handle)
end

function get_collection_names(database::Database; options::Union{Nothing, BSON}=nothing) :: Vector{String}
    result = Vector{String}()
    for bson_collection in find_collections(database, options=options)
        push!(result, bson_collection["name"])
    end
    return result
end

# Aux function to add _id field to document if it does not exist.
function _new_id(document::BSON)
    if haskey(document, "_id")
        return document, nothing
    else
        inserted_oid = BSONObjectId()
        document = deepcopy(document) # copies it so this function doesn't have side effects
        document["_id"] = inserted_oid
        return document, inserted_oid
    end
end

function insert_one(collection::Collection, document::BSON; options::Union{Nothing, BSON}=nothing) :: InsertOneResult
    document, inserted_oid = _new_id(document)
    reply = BSON()
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    ok = mongoc_collection_insert_one(collection.handle, document.handle, options_handle, reply.handle, err)
    if !ok
        error("$err.")
    end
    return InsertOneResult(reply, string(inserted_oid))
end

function delete_one(collection::Collection, selector::BSON; options::Union{Nothing, BSON}=nothing)
    reply = BSON()
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    ok = mongoc_collection_delete_one(collection.handle, selector.handle, options_handle, reply.handle, err)
    if !ok
        error("$err.")
    end
    return reply
end

function delete_many(collection::Collection, selector::BSON; options::Union{Nothing, BSON}=nothing)
    reply = BSON()
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    ok = mongoc_collection_delete_many(collection.handle, selector.handle, options_handle, reply.handle, err)
    if !ok
        error("$err.")
    end
    return reply
end

function update_one(collection::Collection, selector::BSON, update::BSON; options::Union{Nothing, BSON}=nothing)
    reply = BSON()
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    ok = mongoc_collection_update_one(collection.handle, selector.handle, update.handle, options_handle, reply.handle, err)
    if !ok
        error("$err.")
    end
    return reply
end

function update_many(collection::Collection, selector::BSON, update::BSON; options::Union{Nothing, BSON}=nothing)
    reply = BSON()
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    ok = mongoc_collection_update_many(collection.handle, selector.handle, update.handle, options_handle, reply.handle, err)
    if !ok
        error("$err.")
    end
    return reply
end

BulkOperationResult(reply::BSON, server_id::UInt32) = BulkOperationResult(reply, server_id, Vector{Union{Nothing, BSONObjectId}}())

function execute!(bulk_operation::BulkOperation) :: BulkOperationResult
    if bulk_operation.executed
        error("Bulk operation was already executed.")
    end

    try
        reply = BSON()
        err = BSONError()
        bulk_operation_result = mongoc_bulk_operation_execute(bulk_operation.handle, reply.handle, err)
        if bulk_operation_result == 0
            error("Bulk operation execution failed. $err.")
        end
        return BulkOperationResult(reply, bulk_operation_result)
    finally
        destroy!(bulk_operation)
    end
end

function bulk_insert!(bulk_operation::BulkOperation, document::BSON; options::Union{Nothing, BSON}=nothing)
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    ok = mongoc_bulk_operation_insert_with_opts(bulk_operation.handle, document.handle, options_handle, err)
    if !ok
        error("Bulk insert failed. $err.")
    end
    nothing
end

function insert_many(collection::Collection, documents::Vector{BSON}; bulk_options::Union{Nothing, BSON}=nothing, insert_options::Union{Nothing, BSON}=nothing)
    inserted_oids = Vector{Union{Nothing, String}}()

    bulk_operation = BulkOperation(collection, options=bulk_options)
    for doc in documents
        doc, inserted_oid = _new_id(doc)
        bulk_insert!(bulk_operation, doc, options=insert_options)
        push!(inserted_oids, string(inserted_oid))
    end
    result = execute!(bulk_operation)
    append!(result.inserted_oids, inserted_oids)
    return result
end

function find(collection::Collection, bson_filter::BSON=BSON(); options::Union{Nothing, BSON}=nothing) :: Cursor
    options_handle = options == nothing ? C_NULL : options.handle
    cursor_handle = mongoc_collection_find_with_opts(collection.handle, bson_filter.handle, options_handle, C_NULL)
    if cursor_handle == C_NULL
        error("Couldn't execute query.")
    end
    return Cursor(cursor_handle)
end

function count_documents(collection::Collection, bson_filter::BSON=BSON(); options::Union{Nothing, BSON}=nothing)
    err = BSONError()
    options_handle = options == nothing ? C_NULL : options.handle
    len = mongoc_collection_count_documents(collection.handle, bson_filter.handle, options_handle, C_NULL, C_NULL, err)
    if len == -1
        error("Couldn't count number of elements in $collection. $err.")
    end
    return Int(len)
end

function set_limit!(cursor::Cursor, limit::Int)
    ok = mongoc_cursor_set_limit(cursor.handle, limit)
    if !ok
        error("Couldn't set cursor limit to $limit.")
    end
    nothing
end

"""
    find_one(collection::Collection, bson_filter::BSON=BSON(); options::Union{Nothing, BSON}=nothing) :: Union{Nothing, BSON}

Execute a query to a collection and returns the first element of the result set.

Returns `nothing` if the result set is empty.
"""
function find_one(collection::Collection, bson_filter::BSON=BSON(); options::Union{Nothing, BSON}=nothing) :: Union{Nothing, BSON}
    cursor = find(collection, bson_filter, options=options)
    set_limit!(cursor, 1)
    next = _iterate(cursor)
    if next == nothing
        return nothing
    else
        bson_document, _state = next
        return bson_document
    end
end

#
# High-level API
#

function _iterate(cursor::Cursor, state::Nothing=nothing)
    next = BSON()
    handle = next.handle
    handle_ref = Ref{Ptr{Cvoid}}(handle)
    has_next = mongoc_cursor_next(cursor.handle, handle_ref)
    next.handle = handle_ref[]

    if has_next
        # The bson document is valid only until the next call to mongoc_cursor_next.
        # So we should return a deepcopy.
        return deepcopy(next), nothing
    else
        return nothing
    end
end

@static if VERSION < v"0.7-"

    # Iteration protocol for Julia v0.6

    struct CursorIteratorState
        element::Union{Nothing, BSON}
    end

    function Base.start(cursor::Cursor)
        nxt = _iterate(cursor)
        if nxt == nothing
            return CursorIteratorState(nothing)
        else
            next_element, _inner_state = nxt # _inner_state is always nothing
            return CursorIteratorState(next_element)
        end
    end

    Base.done(cursor::Cursor, state::CursorIteratorState) = state.element == nothing

    function Base.next(cursor::Cursor, state::CursorIteratorState)
        @assert state.element != nothing
        nxt = _iterate(cursor)
        if nxt == nothing
            return state.element, CursorIteratorState(nothing)
        else
            next_element, _inner_state = nxt # _inner_state is always nothing
            return state.element, CursorIteratorState(next_element)
        end
    end
else
    # Iteration protocol for Julia v0.7 and v1.0
    Base.iterate(cursor::Cursor, state::Nothing=nothing) = _iterate(cursor, state)
end

Base.show(io::IO, uri::URI) = print(io, "URI(\"", uri.uri, "\")")
Base.show(io::IO, client::Client) = print(io, "Client(URI(\"", client.uri, "\"))")
Base.show(io::IO, db::Database) = print(io, "Database($(db.client), \"", db.name, "\")")
Base.show(io::IO, coll::Collection) = print(io, "Collection($(coll.database), \"", coll.name, "\")")

Base.getindex(client::Client, database::String) = Database(client, database)
Base.getindex(database::Database, collection_name::String) = Collection(database, collection_name)

Base.push!(collection::Collection, document::BSON; options::Union{Nothing, BSON}=nothing) = insert_one(collection, document; options=options)
Base.append!(collection::Collection, documents::Vector{BSON}; bulk_options::Union{Nothing, BSON}=nothing, insert_options::Union{Nothing, BSON}=nothing) = insert_many(collection, documents; bulk_options=bulk_options, insert_options=insert_options)

Base.length(collection::Collection, bson_filter::BSON=BSON(); options::Union{Nothing, BSON}=nothing) = count_documents(collection, bson_filter; options=options)
Base.isempty(collection::Collection, bson_filter::BSON=BSON(); options::Union{Nothing, BSON}=nothing) = count_documents(collection, bson_filter; options=options) == 0