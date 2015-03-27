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
nextComponentId = 0

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

                ret = member.apply @, arguments

                if componentDebug
                    _debugDepth -= 1
                    _popDebugFlag()
                ret

    propSpecs = _.clone componentSpec.props ? {}
    propSpecs.className ?=
        type: React.PropTypes.string
    propSpecs.children ?=
        type: React.PropTypes.oneOfType [
            React.PropTypes.element
            React.PropTypes.arrayOf(React.PropTypes.element)
        ]

    reactSpec.displayName = componentName

    reactSpec.propTypes = {} # TODO


    # Make getter/setter fields for @state, e.g. @a gets/sets @state.a
    for stateFieldName, stateFieldSpec of componentSpec.state ? {}
        if stateFieldName of reactSpec
            throw new Meteor.Error "Name conflict between #{componentName}.#{stateFieldName} and
                #{componentName}.state.#{stateFieldName}"

        reactSpec[stateFieldName] = do (stateFieldName) -> (value) ->
            if arguments.length > 0 and value is undefined
                throw new Meteor.Error "Can't pass undefined to #{componentName}.#{stateFieldName}"
            else if value is undefined
                # Getter
                _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug

                ret = @state[stateFieldName].get()

                if componentDebug
                    console.debug _getDebugPrefix(@), "#{stateFieldName}()", ret
                _popDebugFlag()

                ret
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

            if isLastRoute and lastRoute.name?
                newPath = @makeGoodPath lastRoute.name,
                    newRouteSpec.get('params')?.toObj() ? {},
                    newRouteSpec.get('query')?.toObj() ? {}
                if newPath isnt URI().resource()
                    # TODO: Block the re-rendering here; it's completely unnecessary.
                    # console.debug 'PUSH', newPath
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
        @_componentId = nextComponentId
        nextComponentId += 1
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
        @prop = {} # Reactive getters for the props
        for propName, propSpec of propSpecs
            if propName of @props and @props[propName] is undefined
                throw new Meteor.Error "Can't pass undefined #{@}.props.#{propName}"

            initialValue = J.util.withoutUndefined @props[propName]
            @_props[propName] = J.Var initialValue,
                tag:
                    component: @
                    propName: propName
                    tag: "#{@toString()}.prop.#{propName}"
                onChange: if propSpec.onChange? then do (propName, propSpec) =>
                    (oldValue, newValue) =>
                        _pushDebugFlag propSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug _getDebugPrefix(@), "prop.#{propName}.onChange!"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue

                        propSpec.onChange.call @, oldValue, newValue

                        _popDebugFlag()

            @prop[propName] = do (propName, propSpec) => =>
                _pushDebugFlag propSpec.debug ? componentSpec.debug

                ret = @_props[propName].get()

                if componentDebug
                    console.debug _getDebugPrefix(@), "prop.#{propName}()", ret
                _popDebugFlag()

                ret

        # Set up @state
        initialState = {}
        if J.Routable in (componentSpec.mixins ? []) and @stateFromRoute?
            stateFromRoute = J.util.withoutUndefined @stateFromRoute @getParams(), @_cleanQueryFromRaw()
            for stateFieldName, initialValue of stateFromRoute
                if stateFieldName not of componentSpec.state
                    throw new Error "#{@toString()}.stateFromRoute returned invalid stateFieldName:
                        #{JSON.stringify stateFieldName}"
        else
            stateFromRoute = {}
        for stateFieldName, stateFieldSpec of componentSpec.state
            if stateFromRoute[stateFieldName] isnt undefined
                initialValue = stateFromRoute[stateFieldName]
            else if _.isFunction stateFieldSpec.default
                # TODO: If the type is J.$function then use the other if-branch
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

            initialState[stateFieldName] = J.Var initialValue,
                tag:
                    component: @
                    stateFieldName: stateFieldName
                    tag: "#{@toString()}.state.#{stateFieldName}"
                onChange: if stateFieldSpec.onChange? then do (stateFieldName, stateFieldSpec) =>
                    (oldValue, newValue) =>
                        _pushDebugFlag stateFieldSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug _getDebugPrefix(@), "state.#{stateFieldName}.onChange!"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue

                        stateFieldSpec.onChange.call @, oldValue, newValue

                        _popDebugFlag()

        # Set up @reactives
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

                    if _.isFunction reactiveSpec.onChange then (oldValue, newValue) =>
                        _pushDebugFlag reactiveSpec.debug ? componentSpec.debug
                        if componentDebug
                            console.debug "    #{@toString()}.#{reactiveName}.onChange!"
                            console.debug "        old:", J.util.consolify oldValue
                            console.debug "        new:", J.util.consolify newValue

                        reactiveSpec.onChange.call @, oldValue, newValue

                        _popDebugFlag()
                    else reactiveSpec.onChange ? null

                    component: @
                )

        # This is what React is going to do after this function returns, but we need
        # to do it early because of the synchronous prop onChanges.
        @state = initialState

        # Call all the prop onChange handlers synchronously because they might initialize
        # the state during a cascading React render thread.
        for propName, propVar of @_props
            propVar.onChange? undefined, propVar._value

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

        for propName, newValue of nextProps
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

        J.tryGet(
            => @reactives[reactiveName].get()
            defaultValue
        )



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


Meteor.startup ->
    for componentDef in componentDefinitionQueue
        J._defineComponent componentDef.name, componentDef.spec

    componentDefinitionQueue = null