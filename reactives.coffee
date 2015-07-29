J.ReactivesQueue = new Mongo.Collection "jframework_reactives"
J.ReactivesQueue._ensureIndex priority: -1

unless Meteor.settings.public.isMainMeteor
    Meteor.startup ->
        J.ReactivesQueue.find({ status: "new" }, { sort: { priority: -1 } }).observe
            added: (recalcItem) ->
                modelClass = J.models[recalcItem.mName]
                modelClass.update recalcItem.mId, $set: status: "inProgress"
                instance = modelClass.fetchOne recalcItem.mId
                J.denorm.recalc instance, recalcItem.rName, new Date(), ->
                    modelClass.update recalcItem.mId, $set: status: "done"
