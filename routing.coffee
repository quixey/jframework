J.defineRouter = (routeGenerator) ->
    J._routeGenerator = routeGenerator

if Meteor.isServer
    # Server-side routing is broken, but it's still nice to not
    # break definitions of React components server-side,
    # and some of them try to use the ReactRouter.State mixin.
    J.Routable = {NOT_IMPLEMENTED_YET: true};

if Meteor.isClient
    # Hack J.Routable mixin as a combo of ReactRouter.State + ReactRouter.Navigation
    J.Routable = _.extend _.clone(ReactRouter.State), ReactRouter.Navigation
    J.Routable.contextTypes = _.extend _.clone(ReactRouter.State.contextTypes),
        ReactRouter.Navigation.contextTypes
    _.extend J.Routable,
        _cleanQueryFromRaw: ->
            ###
                Treat x as nonexistent in all these cases:
                    x=&y=5
                    x&y=5
                    y=5
            ###
            query = {}
            for fieldName, value of @getQuery()
                if value then query[fieldName] = URI.decodeQuery(value.replace(/\*hashtag\*/, '#'))
            query


        _rawQueryFromClean: (cleanQuery) ->
            rawQuery = {}
            fieldNames = _.keys cleanQuery
            for fieldName in fieldNames
                value = cleanQuery[fieldName]
                if value then rawQuery[fieldName] = value
            rawQuery


        makeGoodPath: (routeName, params={}, query={}) ->
            URI.decodeQuery(@makePath(
                routeName,
                params,
                @_rawQueryFromClean query
            )).replace(/\ /g, '+').replace(/#/, '*hashtag*')


        getInitialState: ->
            # The logic of reading @stateFromRoute is inlined
            # into components.coffee getInitialState.
            {}


        componentDidMount: ->
            currentRoutes = @getRoutes()
            lastRoute = currentRoutes[currentRoutes.length - 1]
            isLastRoute = lastRoute.handler.displayName is @constructor.displayName

            if isLastRoute and lastRoute.name?
                routePieces = if @routeFromState? then @routeFromState(@state) else {}
                newPath = @makeGoodPath lastRoute.name, routePieces.params, routePieces.query

                if newPath isnt URI().resource()
                    # TODO: Block the re-rendering here; it's completely unnecessary.
                    console.log 'REPLACE', newPath
                    ReactRouter.HistoryLocation.replace newPath


        componentWillReceiveProps: (nextProps) ->
            ###
            Hacked this into the Meteor lifecycle in components.coffee
            if @stateFromRoute?
                @setState @stateFromRoute @getParams(), @_cleanQueryFromRaw()
            ###


        componentDidUpdate: (prevProps, prevState) ->
            currentRoutes = @getRoutes()
            lastRoute = currentRoutes[currentRoutes.length - 1]
            isLastRoute = lastRoute.handler.displayName is @constructor.displayName

            if isLastRoute and lastRoute.name?
                routePieces = if @routeFromState? then @routeFromState(@state) else {}
                newPath = @makeGoodPath lastRoute.name, routePieces.params, routePieces.query
                if newPath isnt URI().resource()
                    # TODO: Block the re-rendering here; it's completely unnecessary.
                    # console.log 'PUSH', newPath
                    ReactRouter.HistoryLocation.push newPath


    J.subscriptions = {}
    Meteor.startup ->
        J.subscriptions.init = Meteor.subscribe 'init'

if Meteor.isClient then Meteor.startup ->
    rootRoute = J._routeGenerator()

    onSubscriptionReady = ->
        ReactRouter.run rootRoute, ReactRouter.HistoryLocation, (Handler, state) ->
            React.render $$(Handler), document.body

    Meteor.autorun (c) ->
        if J.subscriptions.init.ready()
            c.stop()

            # setTimeout to get out of this dead Meteor computation
            setTimeout onSubscriptionReady, 1