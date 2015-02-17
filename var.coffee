class J.VALUE_NOT_READY extends Error
    constructor: ->
        @message = "Value not ready."

J.makeValueNotReadyObject = ->
    e = Error()
    obj = new J.VALUE_NOT_READY
    obj.isServer = Meteor.isServer
    obj.stack = e.stack
    obj


class J.Var
    ###
        TODO: Fancy granular deps
            general:
                equals
            numbers:
                lessThan, greaterThan, lessThanOrEq, greaterThanOrEq
            arrays:
                contains (can keep an object-set for this)
    ###

    constructor: (value, options) ->
        ###
            Options:
                tag: A toString-able object for debugging
                onChange: function(oldValue, newValue) or null
                creator: The computation that "created" this var,
                    which makes this var not active when it
                    invalidates.
        ###

        if arguments.length is 0
            value = J.makeValueNotReadyObject()

        unless @ instanceof J.Var
            return new J.Var value, options

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        if options?.creator is undefined
            @creator = Tracker.currentComputation ? null
        else if options.creator instanceof Tracker.Computation or not options.creator?
            @creator = options.creator
        else
            throw new Meteor.Error "Invalid Var creator: #{options.creator}"

        @tag = options?.tag
        if _.isFunction options?.onChange
            @onChange = options.onChange
        else if options?.onChange?
            throw new Meteor.Error "Invalid Var onChange: #{options.onChange}"
        else
            @onChange = null

        @_getters = {} # computationId: computation

        ###
            @_value is never undefined. It can be J.VALUE_NOT_READY
            which causes get() to either throw VALUE_NOT_READY or return
            undefined when there is no active computation.
        ###
        @_previousReadyValue = undefined
        @_value = @constructor.wrap value


    get: ->
        getter = Tracker.currentComputation

        canGet = @isActive() # or (getter? and getter is @creator)
        if not canGet
            throw new Meteor.Error "Can't get value of inactive Var: #{@}"

        if getter? and getter._id not of @_getters
            if getter._id not of @_getters
                @_getters[getter._id] = getter
                getter.gets ?= {} # computationId: computation
                getter.gets[@_id] = @
                getter.onInvalidate =>
                    delete getter.gets[@_id]
                    delete @_getters[getter._id]

        if @_value instanceof J.VALUE_NOT_READY
            if getter then throw @_value
            undefined
        else
            @_value


    isActive: ->
        not @creator?.invalidated


    set: (value) ->
        setter = Tracker.currentComputation
        canSet = @isActive() # or (setter? and setter is @creator)
        if not canSet
            throw new Meteor.Error "Can't set value of inactive Var: #{@}"

        previousValue = @_value
        @_value = @constructor.wrap value

        if previousValue not instanceof J.VALUE_NOT_READY
            @_previousReadyValue = previousValue

        if not J.util.equals previousValue, @_value
            for getterId, getter of @_getters
                unless getter is setter is @creator
                    getter.invalidate()

        if (
            @onChange? and
            @_value not instanceof J.VALUE_NOT_READY and
            not J.util.equals @_previousReadyValue, @_value
        )
            # Need lexically scoped oldValue and newValue because the
            # current behavior is to save a series of changes.
            # E.g. @set(4), @set(7), @set(3) can all happen synchronously
            # and cause @onChange(undefined, 4), @onChange(4, 7) and
            # @onChange(7, 3) to both be called after flush, in the correct
            # order of course.
            oldValue = @_previousReadyValue
            newValue = @_value

            Tracker.afterFlush =>
                # Only call onChange if we're still active, even though
                # there may be multiple onChange calls queued up from when
                # we were still active.
                if @isActive()
                    @onChange.call @, oldValue, newValue

        @_value


    toString: ->
        s = "Var[#{@_id}](#{J.util.stringifyTag @tag ? ''}=#{J.util.stringify @_value})"
        if not @isActive() then s += " (inactive)"
        s


    tryGet: ->
        J.util.tryGet => @get()


    @isValidValue: (value) ->
        not (
            value is undefined or
            value instanceof J.AutoVar
        )

    @wrap: (value) ->
        if value is undefined
            throw new Meteor.Error "Can't set Var value to undefined. Use
                null or new J.VALUE_NOT_READY instead."
        else if not @isValidValue value
            throw new Meteor.Error "Invalid value for Var: #{value}"

        if value instanceof J.VALUE_NOT_READY
            value
        else if J.util.isPlainObject value
            J.Dict value
        else if _.isArray(value)
            J.List value
        else if value instanceof J.Var
            # Prevent any nested J.Var situation
            try
                value.get()
            catch e
                throw e unless e instanceof J.VALUE_NOT_READY
                e
        else
            value