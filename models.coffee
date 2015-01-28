###
  TODO:
  * Each fieldspec should be declared with type, default value (optional) and docstring (optional)
  * isValid() function so we can't insert/update an invalid model
  * key() function which either returns _id or is computed from other fields
    with a field type system to have a special value to indicate when _id is computed,
    like a "key" type for the _id, as opposed to being its own entropy.
    It's saying whether "_id" is part of the Normalized Kernel.
###




J.Model = ->

_.extend J.Model,
    fromJSONValue: (jsonValue) ->
        ###
            jsonValue is *not* of the form {$type: ThisModelName, $value: someValue}.
            It's just the someValue part.
        ###

        unless J.util.isPlainObject jsonValue
            throw new Meteor.Error 'Override J.Model.fromJSONValue to decode non-object values'

        for fieldName, value of jsonValue
            throw new Meteor.Error "Bad jsonValue for #{@modelName}: #{jsonValue}" if fieldName[0] is '$'

        m = new @ EJSON.fromJSONValue jsonValue


_.extend J.Model.prototype,
    clone: ->
        doc = @toDoc()

        # FIXME: This is a temporary hack because the existence
        # of an _id is currently the only thing that tips off the
        # application layer whether an entity is new/existing,
        # but at the same time entities whose fieldSpec says
        # _id: J.PropTypes.key have their ids auto-generated
        # from their other fields.
        # We need a more serious framework for saved/unsaved
        # and bound/unbound model instances ASAP.
        if doc._id? and not @_id? then delete doc._id

        @modelClass.fromJSONValue doc

    fields: (fields) ->
        if fields?
            for fieldName, value of fields
                if fieldName is '_id'
                    throw new Meteor.Error "Can't set #{@modelName}._id as a field,
                        but you can do it at constructor-time."
                else if fieldName of @modelClass.fieldSpecs
                    @_fields[fieldName] = value
                else
                    throw new Meteor.Error "Class #{@modelName} has no field named #{JSON.stringify fieldName}"
            null
        else
            @_fields

    insert: (callback) ->
        @modelClass.insert @, callback

    remove: (callback) ->
        unless @_id?
            throw new Meteor.Error "Can't remove #{@modelName} instance without an _id"

        @modelClass.remove @_id, callback

    save: (callback) ->
        if @_id?
            doc = @toDoc()
            delete doc._id

            @modelClass.collection.upsert @_id,
                $set: doc,
                callback
            null
        else
            @insert callback

    toDoc: ->
        # Returns an EJSON object with all the
        # user-defined types serialized into JSON, but
        # not the EJSON primitives (Date and Binary).
        # (A "compound EJSON object" can contain user-defined
        # types in the form of J.Model instances.)

        toPrimitiveEjsonObj = (value) ->
            if value instanceof J.Model
                value.toDoc()
            else if _.isArray value
                (toPrimitiveEjsonObj v for v in value)
            else if J.util.isPlainObject value
                ret = {}
                for k, v of value
                    ret[k] = toPrimitiveEjsonObj v
                ret
            else
                value

        doc = toPrimitiveEjsonObj @_fields

        if @_id?
            doc._id = @_id
        else if @modelClass.fieldSpecs._id is J.PropTypes.key
            doc._id = @key()

        doc

    toJSONValue: ->
        ###
            Used by Meteor EJSON.
            Note that the name is misleading because
            EJSON's special primitives (Date and Binary)
            aren't returned as JSON.
        ###
        @toDoc()


    toString: ->
        EJSON.stringify @

    typeName: ->
        ### Used by Meteor EJSON ###
        @modelName

    update: (args...) ->
        unless @_id?
            throw new Meteor.Error "Can't update #{@modelName} instance without an _id"

        @modelClass.collection.update.bind(@modelClass.collection, @_id).apply null, args



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
    modelConstructor = (initFields = {}) ->
        @_id = initFields._id ? null
        @_fields = {}

        fields = _.clone initFields
        delete fields._id
        @fields fields

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
    modelClass.prototype.modelName = modelName
    modelClass.prototype.modelClass = modelClass


    # Wire up instance methods for getting/setting fields

    throw new Meteor.Error "#{modelName} fieldSpecs missing _id" unless '_id' of fieldSpecs

    _.each fieldSpecs, (fieldSpec, fieldName) ->
        return if fieldName is '_id'

        modelClass.prototype[fieldName] = () ->
            if arguments.length == 0
                @_fields[fieldName]
            else
                @_fields[fieldName] = arguments[0]
                null


    # Wire up class methods for collection operations

    if collectionName?
        collection = new Mongo.Collection collectionName,
            transform: (doc) ->
                modelClass.fromJSONValue doc

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

                doc = instance.toJSONValue()

                if @fieldSpecs._id is J.PropTypes.key
                    # If the fieldSpec contains this magic "key"
                    # declaration, then propagate the field values
                    # into the key at first-write time.

                    if instance._id?
                        throw new Meteor.Error "#{@name} can't have an _id (#{JSON.stringify instance._id}) at insert time"

                    instance._id = doc._id

                unless J.util.isPlainObject doc
                    throw new Meteor.Error 'Bad argument to #{modelName}.insert: #{doc}'

                instance._id = collection.insert doc, callback

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