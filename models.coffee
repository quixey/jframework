###
  TODO:
  * Each fieldspec should be declared with type, default value (optional) and docstring (optional)
  * isValid() function so we can't insert/update an invalid model
  * key() function which either returns _id or is computed from other fields
    with a field type system to have a special value to indicate when _id is computed,
    like a "key" type for the _id, as opposed to being its own entropy.
    It's saying whether "_id" is part of the Normalized Kernel.
###


class J.Model
    @fromJSONValue: (jsonValue) ->
        ###
            jsonValue is *not* of the form {$type: ThisModelName, $value: someValue}.
            It's just the someValue part.
        ###

        unless J.util.isPlainObject jsonValue
            throw new Meteor.Error 'Must override J.Model.fromJSONValue to decode non-object values'

        for fieldName, value of jsonValue
            if fieldName[0] is '$'
                throw new Meteor.Error "Bad jsonValue for #{@name}: #{jsonValue}"

        @fromDoc jsonValue


    @fromDoc: (doc) ->
        new @ EJSON.fromJSONValue doc


    clone: ->
        doc = Tracker.nonreactive => @toDoc false
        instance = @modelClass.fromDoc doc
        instance.collection = @collection

        # Note that clones are always detached (and alive)
        instance


    fields: (fields) ->
        unless @alive
            throw new Meteor.Error "#{@modelClass.name} ##{@_id} from collection #{@collection} is dead"

        if arguments.length is 0
            @_fields.getObj()
        else
            if @attached
                throw new Meteor.Error "Can't set #{@modelClass.name} ##{@_id} because it is attached
                    to collection #{J.util.toString @collection._name}"
            @_fields.set fields
            null


    get: (fieldName) ->
        @_fields.get fieldName


    insert: (collection = @collection, callback) ->
        if _.isFunction(collection) and arguments.length is 1
            # Can call insert(callback) to use @collection
            # as the collection.
            callback = collection
            collection = @collection

        unless collection instanceof Mongo.Collection
            throw new Meteor.Error "Invalid collection to #{@modelClass.name}.insert"

        if @attached and @collection is collection
            throw new Meteor.Error "Can't insert #{@modelClass.name} instance into its own attached collection"

        unless @alive
            throw new Meteor.Error "Can't insert dead #{@modelClass.name} instance"

        doc = Tracker.nonreactive => @toDoc true
        J.assert J.util.isPlainObject doc
        if not doc._id?
            # The Mongo driver will give us an ID but we
            # can't pass it a null ID.
            delete doc._id

        # Returns @_id
        @_id = collection.insert doc, callback


    remove: (callback) ->
        unless @attached
            throw new Meteor.Error "Can't remove detached #{@modelClass.name} instance."
        unless @alive
            throw new Meteor.Error "Can't remove dead #{@modelClass.name} instance."

        @collection.remove @_id, callback


    save: (collection = @collection, callback) ->
        if _.isFunction(collection) and arguments.length is 1
            # Can call save(callback) to use @collection
            # as the collection.
            callback = collection
            collection = @collection

        unless collection instanceof Mongo.Collection
            throw new Meteor.Error "Invalid collection to #{@modelClass.name}.insert"

        if @attached and @collection is collection
            throw new Meteor.Error "Can't save #{@modelClass.name} instance into its own attached collection"

        unless @alive
            throw new Meteor.Error "Can't save dead #{@modelClass.name} instance"

        doc = Tracker.nonreactive => @toDoc true
        J.assert J.util.isPlainObject doc

        if doc._id?
            @_id = doc._id
            fields = _.clone doc
            delete fields._id
            collection.upsert @_id,
                $set: fields,
                callback
        else
            # The Mongo driver will give us an ID but we
            # can't pass it a null ID
            delete doc._id
            @_id = collection.insert doc, callback

        @_id


    toDoc: (denormalize = false) ->
        # Returns an EJSON object with all the
        # user-defined types serialized into JSON, but
        # not the EJSON primitives (Date and Binary).
        # (A "compound EJSON object" can contain user-defined
        # types in the form of J.Model instances.)

        unless @alive
            throw new Meteor.Error "Can't call toDoc on dead #{@modelClass.name} instance"

        toPrimitiveEjsonObj = (value) ->
            if value instanceof J.Model
                value.toDoc denormalize
            else if _.isArray value
                (toPrimitiveEjsonObj v for v in value)
            else if J.util.isPlainObject value
                ret = {}
                for k, v of value
                    ret[k] = toPrimitiveEjsonObj v
                ret
            else
                value

        doc = toPrimitiveEjsonObj @fields()

        if denormalize and @modelClass.fieldSpecs._id is J.PropTypes.key
            key = @key()
            J.assert not @_id? or @_id is key
            doc._id = key
        else
            doc._id = @_id

        doc


    toJSONValue: ->
        ###
            Used by Meteor EJSON, e.g. EJSON.stringify.
            Note that the name is misleading because
            EJSON's special primitives (Date and Binary)
            aren't returned as JSON.
        ###

        @toDoc false


    toString: ->
        EJSON.stringify @


    typeName: ->
        ### Used by Meteor EJSON ###
        @modelClass.name


    update: (args...) ->
        unless @attached
            throw new Meteor.Error "Can't call update on detached #{@modelClass.name} instance"
        unless @alive
            throw new Meteor.Error "Can't call update on dead #{@modelClass.name} instance"

        unless J.util.isPlainObject(args[0]) and _.all(key[0] is '$' for key of args[0])
            # Calling something like .update(foo: bar) would replace the entire
            # Mongo doc, which is basically always a mistake. We almost always
            # want to call something like .update($set: foo: bar) instead.
            throw new Meteor.Error "Must use a $ operation for #{@modelClass.name}.update"

        @collection.update.bind(@collection, @_id).apply null, args



J.m = J.models = {}


# Queue up all model definitions to help the J
# framework startup sequence. E.g. all models
# must be defined before all components.
modelDefinitionQueue = []

J.dm = J.defineModel = (modelName, collectionName, fieldSpecs = {_id: null}, members = {}, staticMembers = {}) ->
    modelDefinitionQueue.push
        modelName: modelName
        collectionName: collectionName
        fieldSpecs: fieldSpecs
        members: members,
        staticMembers: staticMembers


J._defineModel = (modelName, collectionName, fieldSpecs = {_id: null}, members = {}, staticMembers = {}) ->
    modelConstructor = (initFields = {}, @collection = @modelClass.collection) ->
        @_id = initFields._id ? null

        # @collection is the collection that was queried
        # to obtain this instance, or the original attached
        # clone-ancestor of this instance, or just the
        # default place we're going to be inserting/saving to.

        # If true, this instance reactively receives
        # changes from its collection and is immutable
        # to the application layer.
        # Note that an attached instance always has an _id.
        @attached = false

        # Attached instances die when the collection
        # they came from no longer contains their ID.
        # They never come back to life, but a new
        # attached instance with the same ID may
        # eventually replace them in the collection.
        # Detached instances are always alive.
        @alive = true

        nonIdInitFields = _.clone initFields
        delete nonIdInitFields._id
        nonIdFieldSpecs = _.clone fieldSpecs
        delete nonIdFieldSpecs._id
        @_fields = new J.Dict nonIdInitFields
        @_fields.replaceKeys _.keys nonIdFieldSpecs

        if @_id? and @modelClass.fieldSpecs._id is J.PropTypes.key
            unless @_id is @key()
                console.warn "#{@modelName}._id is #{@_id} but key() is #{@key()}"

        null

    # Hack to set up the read-only Function.name value
    # for the class. Having the right Function.name is useful
    # for console debugging.
    eval """
        function #{modelName}() {
            return modelConstructor.apply(this, arguments);
        };
        var modelClass = #{modelName};
    """

    _.extend modelClass, J.Model
    _.extend modelClass, staticMembers
    modelClass.collection = null
    modelClass.fieldSpecs = fieldSpecs

    modelClass.prototype = new J.Model()
    _.extend modelClass.prototype, members
    modelClass.prototype.modelClass = modelClass


    # Wire up instance methods for getting/setting fields

    throw new Meteor.Error "#{modelName} fieldSpecs missing _id" unless '_id' of fieldSpecs

    for fieldName, fieldSpec of fieldSpecs
        continue if fieldName is '_id'

        modelClass.prototype[fieldName] ?= do (fieldName) -> (value) ->
            if arguments.length is 0
                # Getter
                @get fieldName
            else
                setter = {}
                setter[fieldName] = value
                @fields setter


    # Wire up class methods for collection operations

    if collectionName?
        collection = new Mongo.Collection collectionName,
            transform: (doc) ->
                J.assert doc._id of collection._attachedInstances
                collection._attachedInstances[doc._id]

        collection._attachedInstances = {} # _id: instance

        collection.find().observeChanges
            added: (id, fields) ->
                doc = _.clone fields
                doc._id = id
                instance = modelClass.fromJSONValue doc
                instance.collection = collection
                instance.attached = true
                collection._attachedInstances[id] = instance

            changed: (id, fields) ->
                instance = collection._attachedInstances[id]
                instance._fields.set fields

            removed: (id) ->
                collection._attachedInstances[id].alive = false
                delete collection._attachedInstances[id]

        _.extend modelClass,
            collection: collection,
            fetchDict: (docIdsOrQuery) ->
                query =
                    if _.isArray docIdsOrQuery
                        _id: $in: docIdsOrQuery
                    else
                        docIdsOrQuery
                instances = @find(query).fetch()
                instanceById = {}
                for instance in instances
                    instanceById[instance._id] = instance
                instanceById

            fetchList: (docIds, includeHoles = false) ->
                instanceDict = @fetchDict docIds
                instanceList = []
                for docId in docIds
                    if instanceDict[docId]?
                        instanceList.push instanceDict[docId]
                    else if includeHoles
                        instanceList.push null
                instanceList

            find: collection.find.bind collection
            findOne: collection.findOne.bind collection
            insert: (instance, callback) ->
                unless instance instanceof modelClass
                    throw new Meteor.Error "#{@name}.insert requires #{@name} instance."
                instance.insert collection, callback

            update: collection.update.bind collection
            upsert: collection.upsert.bind collection
            remove: collection.remove.bind collection

    J.models[modelName] = modelClass
    $$[modelName] = modelClass

    EJSON.addType modelName, modelClass.fromJSONValue.bind modelClass


Meteor.startup ->
    for modelDef in modelDefinitionQueue
        J._defineModel modelDef.modelName, modelDef.collectionName, modelDef.fieldSpecs, modelDef.members, modelDef.staticMembers

    modelDefinitionQueue = null