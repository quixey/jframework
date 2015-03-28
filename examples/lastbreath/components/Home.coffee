J.dc 'Home',
    mixins: [J.Routable]

    state:
        username:
            default: "Guest#{10000 + Math.floor Math.random() * 90000}"


    componentDidMount: ->
        @refs.chatRoom.focus()


    render: ->
        $$ ('div'),
            {}

            $$ ('div'),
                style:
                    fontSize: 36
                    marginBottom: 20
                ("LastBreath")

            $$ ('ChatRoom'),
                ref: 'chatRoom'
                username: @username()
                onSubmitUsername: (e) =>
                    @username e.username