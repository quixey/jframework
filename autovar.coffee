class J.AutoVar
    constructor: (valueFunc, onChange = null, equalsFunc = J.util.equals) ->
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
            return new J.AutoVar valueFunc, onChange, equalsFunc

        unless _.isFunction(valueFunc)
            throw new Meteor.Error "AutoVar must be constructed with valueFunc"

        unless onChange is null or _.isFunction(onChange) or onChange is true
            throw new Meteor.Error "Invalid onChange argument: #{onChange}"

        @valueFunc = valueFunc
        @onChange = onChange
        @equalsFunc = equalsFunc

        @_var = new ReactiveVar undefined, @equalsFunc

        @active = true
        if Tracker.active then Tracker.onInvalidate => @stop()

        @_valueComp = null
        if @onChange? then @_setupValueComp()

    _worthRecomputing: ->
        @_var.dep.hasDependents() or @onChange?

    _recompute: ->
        oldValue = Tracker.nonreactive => @_var.get()
        newValue = J.Dict._deepReactify @valueFunc.call null
        if newValue is undefined
            throw new Meteor.Error "AutoVar.valueFunc must not return undefined"

        @_var.set newValue

        unless @equalsFunc oldValue, newValue
            if _.isFunction(@onChange)
                Tracker.afterFlush =>
                    @onChange.call @, oldValue, newValue

    _setupValueComp: ->
        @_valueComp?.stop()
        @_valueComp = Tracker.nonreactive => Tracker.autorun (valueComp) =>
            @_recompute()

            valueComp.onInvalidate =>
                unless @_worthRecomputing()
                    @_valueComp.stop()

    get: ->
        unless @active
            throw new Meteor.Error "#{@constructor.name} is stopped"

        if not @_valueComp? or @_valueComp.invalidated
            @_setupValueComp()

        @_var.get()

    replaceValueFunc: (@valueFunc) ->
        @_valueComp.invalidate()

    set: ->
        throw new Meteor.Error "There is no AutoVar.set"

    stop: ->
        if @active
            @_valueComp.stop()
            @active = false

    toString: ->
        # Reactive
        "AutoVar(#{J.util.stringify @get()})"