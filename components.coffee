###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

J.components = {}

# J.c et al store a reference to every mounted
# component for easy console debugging.
J.c = J._componentById = {} # componentId: component
J.cid = J._componentDomById = {} # componentId: componentDOMNode
J.cn = J._componentsByName = {} # componentName: {componentId: component}
J.cd = J._componentDomsByName = {} # componentName: {componentId: componentDOMNode}
J._nextComponentId = 0

# Queue up all component definitions to help the J
# framework startup sequence. E.g. all models
# must be defined before all components.
componentDefinitionQueue = []

componentDebug = Meteor.settings?.public?.jframework?.debug?.components ? false
componentDebugStack = []
_pushDebugFlag = (flag = null) ->
    componentDebugStack.push componentDebug
    componentDebug = flag ? componentDebug
_popDebugFlag = ->
    J.assert componentDebugStack.length > 0
    componentDebug = componentDebugStack.pop()

_debugDepth = 0
_getDebugPrefix = (component = null, tabWidth = 4) ->
    numSpaces = Math.max 0, tabWidth * (_debugDepth + 1) - 1
    "#{(' 'for i in [0...numSpaces]).join('')}#{if component? and _debugDepth is 0 then component.toString() else ''}"


J.dc = J.defineComponent = (componentName, componentSpec) ->
    componentDefinitionQueue.push
        name: componentName
        spec: componentSpec



# Transform J.List to array anywhere in the element children hierarchy
# and J.Dicts to plain objects in the case of the "style" property
unpackRenderSpec = (elem) ->
    if React.isValidElement elem
        if _.isArray elem.props.children
            elem.props.children = (unpackRenderSpec e for e in elem.props.children)
        else if elem.props.children?
            elem.props.children = unpackRenderSpec elem.props.children
        if elem.props.style instanceof J.Dict
            elem.props.style = elem.props.style.toObj()
        elem
    else if elem instanceof J.List
        unpackRenderSpec e for e in elem.getValues()
    else if _.isArray elem
        unpackRenderSpec e for e in elem
    else
        elem


J._defineComponent = (componentName, componentSpec) ->
    for memberName in [
        'getDefaultProps'
        'getInitialState'
        'componentWillReceiveProps'
        'shouldComponentUpdate'
        'componentWillUpdate'
    ]
        if memberName of componentSpec
            throw new Meteor.Error "Unnecessary to define #{memberName} for JFramework components
                (in #{componentName})"
    if componentSpec.componentDidUpdate? and componentSpec.componentDidUpdate.length > 0
        throw new Meteor.Error "J.Component.componentDidUpdate methods can't take
            arguments. Use reactive expressions if you care about that stuff."

    unless _.isFunction componentSpec.render
        throw new Meteor.Error "Missing #{componentName}.render method"

    reactSpec = _.clone componentSpec
    delete reactSpec.props
    delete reactSpec.state
    delete reactSpec.reactives
    delete reactSpec.debug

    # Wrap function calls with debug logs
    for memberName, member of componentSpec
        if memberName isnt 'render' and _.isFunction member
            reactSpec[memberName] = do (memberName, member) -> ->
                _pushDebugFlag componentSpec.debug
                if componentDebug
                    console.debug _getDebugPrefix(@), "#{memberName}!"
                    _debugDepth += 1

                memberValue = member.apply @, arguments

                if componentDebug
                    _debugDepth -= 1
                    _popDebugFlag()
                memberValue

    propSpecs = _.clone componentSpec.props ? {}
    propSpecs.className ?=
        type: $$.str
    propSpecs.children ?=
        type: $$.or(
            $$.elem
            $$.list of: $$.elem
        )

    reactSpec.displayName = componentName

    reactSpec.propTypes = {} # TODO


    # Make getter/setter fields for @state, e.g. @a gets/sets @state.a
    for stateFieldName, stateFieldSpec of componentSpec.state ? {}
        if stateFieldName of reactSpec
            throw new Meteor.Error "Name conflict between #{componentName}.#{stateFieldName} and
                #{componentName}.state.#{stateFieldName}"

        reactSpec[stateFieldName] = do (stateFieldName) -> (value) ->
            if arguments.length > 0 and value is undefined
                throw new Error "Can't pass undefined to #{componentName}.#{stateFieldName}"
            else if value is undefined
                # Getter
                _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug

                stateValue = @state[stateFieldName].get()

                if componentDebug
                    console.debug _getDebugPrefix(@), "#{stateFieldName}()", stateValue
                _popDebugFlag()

                stateValue
            else
                # Setter
                stateFields = {}
                stateFields[stateFieldName] = value
                @set stateFields


    # Make reactive getters for @reactives, e.g. @a gets/sets @reactives.a

    # For J.Routable components, make sure there is an explicit or implicit route reactive.
    # This reactive has the special ability to return dicts with undefined values because
    # we wrap it in withoutUndefined.
    reactiveSpecByName = _.clone componentSpec.reactives ? {}
    if J.Routable in (componentSpec.mixins ? [])
        ###
            Set up reactives._urlWatcher whose onChange triggers stateFromRoute. This
            onChange handler should run *before* the first onChange handler of
            reactives.route.
        ###
        if componentSpec.stateFromRoute?
            reactiveSpecByName._urlWatcher =
                val: ->
                    J._urlVar.get()
                early: true
                onChange: (oldUrl, newUrl) ->
                    stateFromRoute = J.util.withoutUndefined @stateFromRoute @getParams(), @_cleanQueryFromRaw()
                    for stateFieldName, initialValue of stateFromRoute
                        if stateFieldName not of componentSpec.state
                            throw new Error "#{@toString()}.stateFromRoute returned invalid stateFieldName:
                                    #{JSON.stringify stateFieldName}"
                    _.extend @_canonicalState, stateFromRoute
                    @set stateFromRoute


        ###
            Set up reactives.route.
        ###
        origRouteValFunc = reactiveSpecByName.route?.val ? ->
            params: {}
            query: {}
        reactiveSpecByName.route ?= {}
        reactiveSpecByName.route.val = ->
            J.util.withoutUndefined origRouteValFunc.call @

        pushNewRoute = (oldRouteSpec, newRouteSpec) ->
            currentRoutes = @getRoutes()
            lastRoute = currentRoutes[currentRoutes.length - 1]
            isLastRoute = lastRoute.handler.displayName is @constructor.displayName
            console.log 'pushNewRoute', @toString(), isLastRoute, lastRoute.name, oldRouteSpec?.toObj(), newRouteSpec?.toObj()

            if isLastRoute and lastRoute.name?
                newParams = newRouteSpec.get('params')?.toObj() ? {}
                newQuery = newRouteSpec.get('query')?.toObj() ? {}
                newStateDelta =
                    if @stateFromRoute?
                        J.util.withoutUndefined @stateFromRoute newParams, newQuery
                    else
                        {}

                oldStateFields = J.Dict()
                for stateFieldName, stateFieldValue of newStateDelta
                    oldStateFields.setOrAdd stateFieldName, @_canonicalState[stateFieldName]

                newPath = @makeGoodPath lastRoute.name, newParams, newQuery

                console.log 'Old URI().resource: ', URI().resource()

                console.log "oldStateFields", oldStateFields.toObj(), "newStateDelta", newStateDelta

                console.log newPath, "different?", newPath isnt URI().resource(), "push?", not oldStateFields.deepEquals(newStateDelta)

                if newPath isnt URI().resource()
                    if oldStateFields.deepEquals(newStateDelta)
                        ReactRouter.HistoryLocation.replace newPath
                    else
                        ReactRouter.HistoryLocation.push newPath

        origOnChange = reactiveSpecByName.route.onChange
        if origOnChange?
            reactiveSpecByName.route.onChange = (oldRouteSpec, newRouteSpec) ->
                origOnChange.call @, oldRouteSpec, newRouteSpec
                pushNewRoute.call @, oldRouteSpec, newRouteSpec
        else
            reactiveSpecByName.route.onChange = pushNewRoute

    for reactiveName, reactiveSpec of reactiveSpecByName
        if reactiveName of reactSpec
            throw new Meteor.Error "Name conflict between #{componentName}.#{reactiveName} and
                #{componentName}.reactives.#{reactiveName}"
        unless _.isFunction(reactiveSpec.val)
            throw new Meteor.Error "#{componentName}.reactives.#{reactiveName} must have a val function"

        reactSpec[reactiveName] = do (reactiveName) -> ->
            @reactives[reactiveName].get()


    reactSpec.getDefaultProps = ->
        defaultProps = {}
        for propName, propSpec of propSpecs
            defaultProps[propName] =
                if 'default' of propSpec
                    propSpec.default
                else
                    null
        defaultProps


    reactSpec.getInitialState = ->
        @_componentId = J._nextComponentId
        J._nextComponentId += 1
        J._componentById[@_componentId] = @
        J._componentsByName[componentName] ?= {}
        J._componentsByName[componentName][@_componentId] = @

        @_valid = J.Var true
        @_showingLoader = false
        @_afterRenderCallbacks = []

        # Check for invalid prop names in @props
        for propName, value of @props
            unless propName of propSpecs
                throw new Meteor.Error "#{componentName} has no prop #{JSON.stringify propName}.
                    Only has #{JSON.stringify _.keys propSpecs}."
        # Set up @prop
        @_props = {} # Vars for the props
        @_lazyProps = {} # Vars for the evaluated lazy props
        @prop = {} # Reactive getters for the props
        for propName, propSpec of propSpecs
            do (propName, propSpec) =>
                if propName of @props and @props[propName] is undefined
                    throw new Meteor.Error "Can't pass undefined #{@}.props.#{propName}"

                initialValue = J.util.withoutUndefined @props[propName]
                # TODO: Validate type of initialValue

                @_props[propName] = J.Var initialValue,
                    tag:
                        component: @
                        propName: propName
                        tag: "#{@toString()}.prop.#{propName}"


                ###
                    @_lazyProps[propName] is a relatively heavy reactive computation that
                    we only need if there's ever a time when prop laziness is used.
                    We also need it if there's a propSpec.onChange, because the semantics
                    of onChange get tricky if and when they mix with laziness semantics.
                ###
                setupLazyProp = =>
                    @_lazyProps[propName] = J.AutoVar(
                        (
                            component: @
                            lazyPropName: propName
                            tag: "Lazy #{@toString()}.prop.#{propName}"
                        )

                        =>
                            propValue = @_props[propName].get()

                            if _.isFunction(propValue) and propSpec.type isnt $$.func
                                propValue()
                            else
                                propValue

                        if propSpec.onChange? then (oldValue, newValue, isEarlyInitTime) =>
                            if oldValue is undefined and not isEarlyInitTime
                                # Since we have a hack to call all the onChange handlers early at component
                                # init time, we need to stifle the onChange function called with the same arguments
                                # again at afterFlush time.
                                return

                            _pushDebugFlag propSpec.debug ? componentSpec.debug
                            if componentDebug
                                console.debug _getDebugPrefix(@), "prop.#{propName}.onChange!
                                    #{if isEarlyInitTime then '(early)' else ''}"
                                console.debug "        old:", J.util.consolify oldValue
                                console.debug "        new:", J.util.consolify newValue

                            propSpec.onChange?.call @, oldValue, newValue

                            _popDebugFlag()

                        creator: null
                    )

                if propSpec.onChange? then setupLazyProp()

                @prop[propName] = =>
                    if @_lazyProps[propName]?
                        _pushDebugFlag propSpec.debug ? componentSpec.debug

                        try
                            propValue = @_lazyProps[propName].get()
                        catch e
                            if e instanceof J.VALUE_NOT_READY
                                propValue = e
                            else
                                throw e

                        if componentDebug
                            console.debug _getDebugPrefix(@), "prop.#{propName}()", propValue
                        _popDebugFlag()

                        if propValue instanceof J.VALUE_NOT_READY
                            throw propValue
                        else
                            return propValue

                    propValue = @_props[propName].get()

                    if _.isFunction(propValue) and propSpec.type isnt $$.func
                        setupLazyProp()
                        @prop[propName]()

                    else
                        propValue



        # Set up @reactives
        # Note that stateFieldSpec.default functions can try calling reactives.
        @reactives = {} # reactiveName: autoVar
        for reactiveName, reactiveSpec of reactiveSpecByName
            @reactives[reactiveName] = do (reactiveName, reactiveSpec) =>
                J.AutoVar(
                    (
                        component: @
                        reactiveName: reactiveName
                        tag: "#{@toString()}.reactives.#{reactiveName}",
                    )

                    =>
                        _pushDebugFlag reactiveSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug _getDebugPrefix(@), "!#{reactiveName}()"
                            _debugDepth += 1

                        try
                            retValue = reactiveSpec.val.call @
                        finally
                            if componentDebug
                                console.debug _getDebugPrefix(), retValue
                                _debugDepth -= 1
                            _popDebugFlag()

                        retValue

                    if _.isFunction reactiveSpec.onChange then (oldValue, newValue, isEarlyInitTime) =>
                        if reactiveSpec.early and oldValue is undefined and not isEarlyInitTime
                            # Since we have a hack to call all the onChange handlers early at component
                            # init time, we need to stifle the onChange function called with the same arguments
                            # again at afterFlush time.
                            return

                        _pushDebugFlag reactiveSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug "    #{@toString()}.#{reactiveName}.onChange!
                                #{if isEarlyInitTime then '(early)' else ''}"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue

                        reactiveSpec.onChange.call @, oldValue, newValue

                        _popDebugFlag()
                    else reactiveSpec.onChange ? null

                    component: @
                )

        # Set up @state
        initialState = {}

        # Keep this around to implement stateFromRoute semantics
        @_canonicalState = {}

        for stateFieldName, stateFieldSpec of componentSpec.state
            if _.isFunction(stateFieldSpec.default) and stateFieldSpec.type isnt $$.func
                _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug
                if componentDebug
                    console.debug _getDebugPrefix(@), "#{stateFieldName} !default()"
                    _debugDepth += 1

                initialValue = stateFieldSpec.default.apply @

                if componentDebug
                    console.debug _getDebugPrefix(), initialValue
                    _debugDepth -= 1
                _popDebugFlag()
            else
                initialValue = stateFieldSpec.default ? null

            @_canonicalState[stateFieldName] = initialValue

            initialState[stateFieldName] = J.Var initialValue,
                tag:
                    component: @
                    stateFieldName: stateFieldName
                    tag: "#{@toString()}.state.#{stateFieldName}"
                onChange: if stateFieldSpec.onChange? then do (stateFieldName, stateFieldSpec) =>
                    (oldValue, newValue, isEarlyInitTime) =>
                        _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug _getDebugPrefix(@), "state.#{stateFieldName}.onChange!
                                #{if isEarlyInitTime then '(early)' else ''}"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue

                        stateFieldSpec.onChange.call @, oldValue, newValue

                        _popDebugFlag()

        # This is what React is going to do after this function returns, but we need
        # to do it early because of the synchronous onChanges.
        @state = initialState

        # Call all the onChange handlers synchronously because they might initialize
        # the state during a cascading React render thread.
        for lazyPropName, lazyPropAutoVar of @_lazyProps
            propVar = @_props[lazyPropName]
            lazyPropAutoVar.onChange? undefined, propVar._value, true
        for reactiveName, reactiveAutoVar of @reactives
            reactiveSpec = reactiveSpecByName[reactiveName]
            if reactiveSpec.early
                reactiveValue = reactiveAutoVar.get()
                reactiveAutoVar.onChange undefined, reactiveValue, true
        for stateFieldName, stateVar of @state
            stateVar.onChange? undefined, stateVar._value, true

        # Return initialState to React
        initialState


    reactSpec.set = (stateFields, callback) ->
        if callback? then @afterRender callback

        for stateFieldName, value of stateFields
            unless stateFieldName of @state
                throw new Meteor.Error "#{componentName}.state.#{stateFieldName} does not exist."
            @state[stateFieldName].set value

        null


    reactSpec.componentWillReceiveProps = (nextProps) ->
        componentSpec.componentWillReceiveProps?.call @, nextProps

        ###
            When props have type $$.dict or $$.list, we'll do a deep comparison
            to avoid unnecessary reactive triggers.
            To switch this behavior to naive J.Var behavior, use type $$.var.
        ###

        for propName, newValue of nextProps
            propSpec = propSpecs[propName]

            if propSpec.type isnt $$.var
                # Consider equal deep values to be equal and skip setting
                # the J.Var to avoid invalidation propagation

                oldValue = Tracker.nonreactive => @_props[propName].get()

                continue if (
                    (oldValue instanceof J.Dict or oldValue instanceof J.List) and
                    oldValue.deepEquals(newValue)
                )

            @_props[propName].set J.util.withoutUndefined newValue


    reactSpec.componentDidMount = ->
        J._componentDomById[@_componentId] = @getDOMNode()
        J._componentDomsByName[componentName] ?= {}
        J._componentDomsByName[componentName][@_componentId] = @getDOMNode()

        componentSpec.componentDidMount?.apply @

        @_doAfterRender()


    reactSpec._doAfterRender = ->
        if @_showingLoader or not @_valid.get()
            # Will try again after render
            return

        prevAfterRenderCallbacks = @_afterRenderCallbacks ? []
        @_afterRenderCallbacks = []
        callback() for callback in prevAfterRenderCallbacks


    reactSpec.shouldComponentUpdate = (nextProps, nextState) ->
        not @_elementVar? or @_elementVar.invalidated


    reactSpec.componentDidUpdate = (prevProps, prevState) ->
        @_doAfterRender()

        componentSpec.componentDidUpdate?.call @


    reactSpec.afterRender = (f) ->
        J.assert not Tracker.active or @_elementVar?._getting, "Can only call afterRender
            from within render function or from outside a reactive computation."

        @_afterRenderCallbacks.push f
        Tracker.afterFlush(
            => @_doAfterRender()
            Number.POSITIVE_INFINITY
        )
        null


    reactSpec.componentWillUnmount = ->
        componentSpec.componentWillUnmount?.apply @

        delete J._componentById[@_componentId]
        delete J._componentDomById[@_componentId]
        delete J._componentsByName[componentName][@_componentId]
        delete J._componentDomsByName[componentName][@_componentId]

        @_valid.set false
        @_elementVar.stop()

        J.fetching._deleteComputationQsRequests @_elementVar
        for lazyPropName, lazyPropVar of @_lazyProps
            lazyPropVar.stop()
        for reactiveName, reactiveVar of @reactives
            reactiveVar.stop()

        # Garbage collector seems to need this
        delete @_elementVar.component
        delete @_elementVar


    reactSpec._hasInvalidAncestor = ->
        ancestor = @
        while ancestor
            if ancestor._valid? and not ancestor._valid.get()
                return true
            ancestor = ancestor._owner
        false


    reactSpec.tryGet = (reactiveName, defaultValue) ->
        if reactiveName not of @reactives
            throw new Meteor.Error "Invalid reactive name: #{@}.#{reactiveName}"

        @reactives[reactiveName].tryGet defaultValue


    reactSpec.tryGetProp = (propName, defaultValue) ->
        if propName not of @_props
            throw new Meteor.Error "Invalid prop name: #{@}.#{propName}"

        J.tryGet @prop[propName], defaultValue


    reactSpec.renderLoader ?= ->
        $$ ('div'),
            style:
                textAlign: 'center'
                opacity: 0.5
            $$ ('Loader')


    reactSpec.render = ->
        if Tracker.active
            throw new Error "Can't call render inside a reactive computation: #{Tracker.currentComputation._id}"

        if @_elementVar? and not @_elementVar.invalidated
            throw new Meteor.Error "Called #{@toString()}.forceUpdate() - J.components
                don't allow forceUpdate(). Use reactive expressions instead."

        _pushDebugFlag componentSpec.debug
        if componentDebug
            console.debug _getDebugPrefix(@), "render!"
            _debugDepth += 1

        if @_elementVar?
            @_elementVar.stop()
            J.fetching._deleteComputationQsRequests @_elementVar
        else
            if false
                # First render
                # Pre-compute all the reactives with onChanges in parallel. This is
                # so we won't waste time fetching data in series when render needs it.
                for reactiveName, reactive of @reactives
                    if reactive.onChange
                        if componentDebug
                            console.debug "Precomputing !#{reactiveName}"
                        reactive.tryGet()

        firstRun = true
        @_elementVar = J.AutoVar(
            (
                component: @
                tag: "#{@toString()}.render"
            )

            (elementVar) =>
                if firstRun
                    firstRun = false
                    Tracker.onInvalidate => @_valid.set false

                    if J.Routable in (componentSpec.mixins ? [])
                        # If the URL changes, that will cause all the Routable
                        # components to need to be re-rendered. Otherwise
                        # shouldComponentUpdate will block ReactRouter functionality.
                        J._urlVar.get()

                    unpackRenderSpec componentSpec.render.apply @

                else
                    elementVar.stop()

                    Tracker.afterFlush(
                        =>
                            if @_elementVar is elementVar and @isMounted()
                                if not (@_owner? and @_owner._hasInvalidAncestor?())
                                    @forceUpdate()
                        @_componentId + 10
                    )

                    null

            null

            component: @
            sortKey: @_componentId + 10
        )

        @_valid.set true

        element = @_elementVar.tryGet()

        if componentDebug
            console.debug _getDebugPrefix(), if element? then "[Rendered #{@}]" else "[Loader for #{@}]"
            _debugDepth -= 1
        _popDebugFlag()

        if element is undefined
            @_showingLoader = true
            @renderLoader()
        else
            @_showingLoader = false
            element


    reactSpec.toString = ->
        "<#{componentName}-#{@_componentId}>"


    J.components[componentName] = React.createClass reactSpec


$$ = (elemType, props, children...) ->
    args = Array.prototype.slice.call arguments

    if typeof elemType[0] is 'string' and elemType[0].toUpperCase() is elemType[0]
        throw new Meteor.Error "No component class #{elemType}." unless elemType of J.components
        args[0] = J.components[elemType]

    React.createElement.apply React, args


J.lazy = (childrenFunc) ->
    componentName = "_Lazy#{J.getNextId()}"

    J._defineComponent componentName,
        _isLazy: true

        render: ->
            childrenFunc()

    $$ (componentName)


Meteor.startup ->
    for componentDef in componentDefinitionQueue
        J._defineComponent componentDef.name, componentDef.spec

    componentDefinitionQueue = null