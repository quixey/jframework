if Meteor.isServer
    Meteor.publish 'test', ->
        transcript = $$.Transcripts.findOne()

