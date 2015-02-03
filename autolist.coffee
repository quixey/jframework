class J.AutoList extends J.List
    constructor: (sizeFunc, valueFunc, onChange = null, equalsFunc = J.util.equals) ->
        unless @ instanceof J.AutoList
            return new J.AutoList sizeFunc, valueFunc, onChange, equalsFunc

        unless _.isFunction(sizeFunc) and _.isFunction(valueFunc)
            throw new Meteor.Error "AutoList must be constructed with sizeFunc and valueFunc"

        super [], equalsFunc

        @sizeFunc = sizeFunc
        @valueFunc = valueFunc
        @onChange = onChange
        @equalsFunc = equalsFunc

        @_dict = J.AutoDict(
            => "#{i}" for i in [0...@sizeFunc()]
            (key) => @valueFunc parseInt(key)
            (
                if _.isFunction @onChange then (key, oldValue, newValue) =>
                    @onChange?.call null, parseInt(key), oldValue, newValue
                else
                    @onChange
            )
            @equalsFunc
        )

    clear: ->
        throw new Meteor.Error "There is no AutoList.clear"

    push: ->
        throw new Meteor.Error "There is no AutoList.push"

    replaceSizeFunc: (@sizeFunc) ->
        @_dict.replaceKeysFunc => "#{i}" for i in [0...@sizeFunc()]

    replaceValueFunc: (@valueFunc) ->
        @_dict.replaceValueFunc @valueFunc

    resize: ->
        throw new Meteor.Error "There is no AutoList.resize"

    reverse: ->
        throw new Meteor.Error "There is no AutoList.reverse"

    set: ->
        throw new Meteor.Error "There is no AutoList.set"

    sort: ->
        throw new Meteor.Error "There is no AutoList.sort"

    toString: ->
        # Reactive
        "AutoList#{J.util.stringify @toArr()}"