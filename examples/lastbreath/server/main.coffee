J.methods
    chat: (username, message, battery) ->
        chat = new $$.Chat
            username: username
            message: message
            timestamp: new Date()
            battery: battery
        chat.save()