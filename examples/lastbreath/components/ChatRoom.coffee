J.dc 'ChatRoom',
    props:
        username:
            type: $$.str
            onChange: (oldUsername, newUsername) ->
                return if oldUsername is undefined
                @messages().push
                    kind: 'Custom'
                    element: $$ ('div'),
                        style:
                            fontSize: 12
                            color: 'green'
                            marginBottom: 4

                        $$ ('span'),
                            {}
                            "Changed username to "

                        $$ ('span'),
                            style:
                                fontWeight: 'bold'
                            (newUsername)
                @afterRender => @focus()
        onSubmitUsername:
            type: $$.func
        width:
            type: $$.num
            default: 600

    state:
        editingUsername:
            default: false
            onChange: (_, editingUsername) ->
                @afterRender =>
                    if editingUsername
                        @refs.inpUsername.getDOMNode().focus()
                        @refs.inpUsername.getDOMNode().select()
                    else
                        @focus()

        seenChatIdSet:
            default: -> J.Dict() # chatId: true

        messages:
            doc: """
                A message can be various kinds:
                    Chat
                        username: Sender username
                        message: Message text
                    Custom
                        element: A ReactElement
            """
            default: -> J.List()

    reactives:
        battery:
            val: -> J.getBattery()
            onChange: true

        chats:
            val: ->
                $$.Chat.fetch(
                    {}
                    sort: timestamp: -1
                    limit: 10
                ).getSorted (chat) -> chat.timestamp()
            onChange: (_, chats) ->
                chats.forEach (chat) =>
                    if not @seenChatIdSet().hasKey chat._id
                        @messages().push
                            kind: 'Chat'
                            username: chat.username()
                            message: chat.message()
                            battery: chat.battery()
                        @seenChatIdSet().setOrAdd chat._id, true

        _messagesScroller:
            val: ->
                @messages().toArr()
            onChange: ->
                @afterRender =>
                    messagesBox = @refs.messagesBox.getDOMNode()
                    messagesBox.scrollTop = messagesBox.scrollHeight

    focus: ->
        @afterRender =>
            @refs.inpMessage.getDOMNode().focus()


    send: ->
        message = @refs.inpMessage.getDOMNode().value
        return if not message

        Meteor.call 'chat', @prop.username(), message, @battery()
        @refs.inpMessage.getDOMNode().value = ''


    submitUsername: ->
        username = @refs.inpUsername.getDOMNode().value.trim()
        return if not username

        @prop.onSubmitUsername()? username: username
        @editingUsername false


    render: ->
        $$ ('div'),
            {}

            $$ ('TableRow'),
                style:
                    fontSize: 14
                    height: 24

                $$ ('td'),
                    style:
                        color: '#999'
                        paddingRight: 4
                    ("Chatting as")

                if @editingUsername()
                    $$ ('td'),
                        {}

                        $$ ('input'),
                            ref: 'inpUsername'
                            type: 'text'
                            style:
                                width: 100
                                fontWeight: 'bold'
                            defaultValue: @prop.username()
                            onKeyDown: (e) =>
                                switch e.key
                                    when 'Enter' then @submitUsername()
                                    when 'Escape' then @editingUsername false

                        $$ ('SubmitCancelDelete'),
                            style:
                                display: 'inline'
                            onSubmit: (e) =>
                                @submitUsername()
                            onCancel: =>
                                @editingUsername false
                            ('Submit')

                else
                    $$ ('td'),
                        {}

                        $$ ('span'),
                            style:
                                fontWeight: 'bold'
                            (@prop.username())

                        (" ")

                        $$ ('EditButton'),
                            onClick: =>
                                @editingUsername true

            $$ ('div'),
                ref: 'messagesBox'
                style:
                    border: '1px solid #ccc'
                    width: @prop.width()
                    height: 400
                    padding: 9
                    overflow: 'auto'

                @messages().map (message) =>
                    if message.kind() is 'Chat'
                        batteryLevel = message.battery().get('level')

                        $$ ('TableRow'),
                            style:
                                background:
                                    if batteryLevel?
                                        J.util.fractionToColor batteryLevel
                                marginBottom: 8

                            $$ ('td'),
                                style:
                                    verticalAlign: 'top'
                                    fontWeight: 'bold'
                                    paddingRight: 4
                                (message.username())

                            $$ ('td'),
                                style:
                                    verticalAlign: 'top'
                                    paddingRight: 12
                                    paddingTop: 2
                                    fontSize: 14
                                    fontWeight: 'bold'
                                    fontFamily: 'courier new'
                                    color: if not batteryLevel? then '#999'

                                if batteryLevel?
                                    "#{parseInt batteryLevel * 100}%"
                                else
                                    ("N/A")

                            $$ ('td'),
                                style:
                                    verticalAlign: 'top'
                                (message.message())
                    else
                        message.element()

            $$ ('input'),
                ref: 'inpMessage'
                type: 'text'
                style:
                    fontSize: 14
                    width: @prop.width()
                    padding: 8
                onKeyDown: (e) =>
                    if e.key is 'Enter' then @send()