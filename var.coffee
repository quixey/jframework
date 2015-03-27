###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###


class J.VALUE_NOT_READY extends Error
    constructor: ->
        @name = "J.VALUE_NOT_READY"
        @message = "Value not ready."

J.makeValueNotReadyObject = ->
    # The commented-out lines are kinda helpful
    # for debugging but slow as hell.
    # e = Error()
    obj = new J.VALUE_NOT_READY
    obj.isServer = Meteor.isServer
    # obj.stack = e.stack
    obj

J.tryGet = (func, defaultValue = undefined) ->
    # If value is ready then return it, otherwise
    # return undefined (rather than throwing)
    try
        func()
    catch e
        throw e unless e instanceof J.VALUE_NOT_READY
        defaultValue


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
                wrap: If true, wrap the argument to @set in a List
                    or Dict if it's an array or plain object.
        ###

        if arguments.length is 0
            value = J.makeValueNotReadyObject()

        unless @ instanceof J.Var and not @_id?
            return new J.Var value, options

        @_id = J.getNextId()
        if J.debugGraph then J.graph[@_id] = @

        if options?.creator is undefined
            @creator = Tracker.currentComputation ? null
        else if options.creator instanceof Tracker.Computation or not options.creator?
            @creator = options.creator
        else
            throw new Meteor.Error "Invalid Var creator: #{options.creator}"
        @creator?.onInvalidate => delete @creator

        @tag = if J.debugTags then J.util.stringifyTag(options?.tag) else null
        if _.isFunction options?.onChange
            @onChange = options.onChange
        else if options?.onChange?
            throw new Meteor.Error "Invalid Var onChange: #{options.onChange}"
        else
            @onChange = null
        @wrap = options?.wrap ? true

        @_getters = [] # computations

        ###
            @_value is never undefined. It can be J.VALUE_NOT_READY
            which causes get() to either throw VALUE_NOT_READY or return
            undefined when there is no active computation.
        ###
        @_previousReadyValue = undefined
        initValue = @_value = @maybeWrap value


    debug: ->
        console.log @toString()


    get: ->
        getter = Tracker.currentComputation

        if not @isActive()
            throw new Meteor.Error "Can't get value of inactive Var: #{@}"

        if getter?
            if getter not in @_getters
                @_getters.push getter
                getter.onInvalidate =>
                    @_getters.splice @_getters.indexOf(getter), 1

            if (
                (@_value instanceof J.List or @_value instanceof J.Dict) and
                @_value.creator?
            )
                # Normally Lists and Dicts control their own reactivity when methods
                # are called on them. The exception is when they get stopped.
                @_value.creator._addSideGetter getter

        if @_value instanceof J.VALUE_NOT_READY
            throw @_value
        else
            @_value


    isActive: ->
        not @creator?.invalidated


    set: (value) ->
        if not @isActive()
            throw new Meteor.Error "Can't set value of inactive Var: #{@}"

        setter = Tracker.currentComputation

        previousValue = @_value
        newValue = @_value = @maybeWrap value

        if @onChange?
            if previousValue not instanceof J.VALUE_NOT_READY
                @_previousReadyValue = previousValue

        if not J.util.equals newValue, previousValue
            for getter in _.clone @_getters
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
            previousReadyValue = @_previousReadyValue
            @_previousReadyValue = undefined # Free the memory

            Tracker.afterFlush =>
                # Only call onChange if we're still active, even though
                # there may be multiple onChange calls queued up from when
                # we were still active.
                if @isActive()
                    @onChange.call @, previousReadyValue, newValue

        @_value


    toString: ->
        s = "Var[#{@_id}](#{J.util.stringifyTag @tag ? ''}=#{J.util.stringify @_value})"
        if not @isActive() then s += " (inactive)"
        s


    tryGet: (defaultValue) ->
        J.tryGet(
            => @get()
            defaultValue
        )


    maybeWrap: (value, withFieldFuncs = true) ->
        if value is undefined
            throw new Meteor.Error "Can't set #{@toString()} value to undefined.
                Use null or new J.VALUE_NOT_READY instead."
        else if value instanceof J.AutoVar
            throw new Meteor.Error "Can't put an AutoVar inside #{@toString()}:
                #{value}. Get its value with .get() first."

        if not @wrap and (_.isArray(value) or J.util.isPlainObject(value))
            return value

        J.Var.wrap value, withFieldFuncs


    @wrap: (value, withFieldFuncs = true) ->
        if value is undefined
            if Tracker.active
                throw new Meteor.Error "Undefined is an invalid value.
                    Use null or new J.VALUE_NOT_READY instead."
            else
                J.makeValueNotReadyObject()
        else if value instanceof J.AutoVar
            throw new Meteor.Error "A whole AutoVar is not a valid:
                value: #{value}. Get its value with .get() first."
        if value instanceof J.VALUE_NOT_READY
            value
        else if J.util.isPlainObject value
            J.Dict value,
                fineGrained: false
                withFieldFuncs: withFieldFuncs
        else if _.isArray(value)
            J.List value,
                fineGrained: false
        else if value instanceof J.Var
            # Prevent any nested J.Var situation
            try
                value.get()
            catch e
                throw e unless e instanceof J.VALUE_NOT_READY
                e
        else
            value
