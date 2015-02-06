###
    TODO:

    Make a J.ReactiveVar class which is like Meteor's ReactiveVar
    but has a bunch of functions powered by finer-grained deps like:
        general:
            equals
        numbers:
            lessThan, greaterThan, lessThanOrEq, greaterThanOrEq
        arrays:
            contains (can keep an object-set for this)
    have J.AutoVar inherit from J.ReactiveVar

###

class J.AutoVar
    constructor: (valueFunc, onChange = null, equalsFunc = J.util.equals, wrap = true) ->
        ###
            AutoVars default to being "lazy", i.e. not calculated
            until .get().

            onChange:
                A function to call with (oldValue, newValue) when
                the value changes.
                May also pass onChange=true or null.
                If onChange is either a function or true, the
                AutoVar becomes non-lazy.
        ###

        unless @ instanceof J.AutoVar
            return new J.AutoVar valueFunc, onChange, equalsFunc, wrap

        unless _.isFunction(valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        unless onChange is null or _.isFunction(onChange) or onChange is true
            throw new Meteor.Error "Invalid onChange argument: #{onChange}"

        @valueFunc = valueFunc
        @onChange = onChange
        @equalsFunc = equalsFunc
        @wrap = wrap

        @_var = new ReactiveVar undefined, @equalsFunc

        @active = true
        if Tracker.active then Tracker.onInvalidate => @stop()

        @_valueComp = null
        if @onChange? then Tracker.afterFlush =>
            if not @_valueComp? then @_setupValueComp()

        @_arrIndexOfDeps = {} # value: dep

    _deepGet: ->
        # Reactive
        ###
            Unwrap any nested AutoVars during get(). This is because
            @valueFunc may get a performance benefit from isolating
            part of its reactive logic in an AutoVar.
        ###
        value = @_var.get()
        if value instanceof J.AutoVar then value.get() else value

    _recompute: ->
        oldValue = Tracker.nonreactive => @_deepGet()
        rawValue = @valueFunc.call null
        newValue =
            if @wrap and rawValue not in [@constructor._UNDEFINED, @constructor._UNDEFINED_WITHOUT_SET]
                J.Dict._deepReactify rawValue
            else
                rawValue

        if newValue is undefined
            throw new Meteor.Error "AutoVar.valueFunc must not return undefined"
        else if newValue is @constructor._UNDEFINED_WITHOUT_SET
            return undefined
        else if newValue is @constructor._UNDEFINED
            newValue = undefined

        @_var.set newValue

        # Check if we should fire @_arr* deps
        oldArr = null
        if oldValue instanceof J.List
            oldArr = Tracker.nonreactive => oldValue.getValues()
        else if _.isArray oldValue
            oldArr = oldValue
        newArr = null
        if newValue instanceof J.List
            newArr = Tracker.nonreactive => newValue.getValues()
        else if _.isArray newValue
            newArr = newValue
        if oldArr? and newArr?
            for x, i in oldArr
                if newArr[i] isnt x
                    @_arrIndexOfDeps[i]?.changed()
            for y, i in newArr
                if oldArr[i] isnt y
                    @_arrIndexOfDeps[i]?.changed()


        unless @equalsFunc oldValue, newValue
            if _.isFunction(@onChange)
                Tracker.afterFlush =>
                    @onChange.call @, oldValue, newValue

    _setupValueComp: ->
        @_valueComp?.stop()
        @_valueComp = Tracker.nonreactive => Tracker.autorun (valueComp) =>
            pos = @constructor._pending.indexOf @
            if pos >= 0
                @constructor._pending.splice pos, 1

            @_recompute()
            valueComp.onInvalidate =>
                unless valueComp.stopped
                    if @ not in @constructor._pending
                        @constructor._pending.push @

    contains: (x) ->
        # Reactive
        @indexOf(x) >= 0

    get: ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped: #{@}"
        if arguments.length
            throw new Meteor.Error "Can't pass argument to AutoVar.get"

        if @_valueComp?
            @constructor.flush()
        else
            @_setupValueComp()

        @_deepGet()

    indexOf: (x) ->
        # Reactive
        value = Tracker.nonreactive =>
            v = @get()
            if v instanceof J.List then v.getValues() else v

        if not _.isArray(value)
            throw new Meteor.Error "Can't call .contains() on AutoVar with
                non-list value: #{J.util.stringify value}"

        i = value.indexOf x

        @_arrIndexOfDeps[x] ?= new Deps.Dependency()
        @_arrIndexOfDeps[x].depend()

        i

    set: ->
        throw new Meteor.Error "There is no AutoVar.set"

    stop: ->
        if @active
            @active = false
            @_valueComp?.stop()
            pos = @constructor._pending.indexOf @
            if pos >= 0
                @constructor._pending.splice pos, 1

    toString: ->
        if @tag?
            "AutoVar(#{@tag}=#{J.util.stringify @_var.get()})"
        else
            "AutoVar(#{J.util.stringify @_var.get()})"


    @_pending: []

    @flush: ->
        while @_pending.length
            av = @_pending.shift()
            av._setupValueComp()

    # Internal classes return this in @_valueFunc
    # in order to make .get() return undefined
    @_UNDEFINED_WITHOUT_SET = {'AutoVar':'UNDEFINED_WITHOUT_SET'}
    @_UNDEFINED = {'AutoVar': 'UNDEFINED'}