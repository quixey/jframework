J.ReactivesQueue = new Mongo.Collection "jframework_reactives"
J.ReactivesQueue._ensureIndex priority: -1

unless Meteor.settings.public.isMainMeteor
    Meteor.startup ->
        J.ReactivesQueue.find({ status: "new" }, { sort: { priority: -1 } }).observe
            added: (recalcItem) ->
                J.ReactivesQueue.update recalcItem._id, $set: status: "inProgress"
                instance = J.models[recalcItem.mName].fetchOne recalcItem.mId
                J.denorm.recalc instance, recalcItem.rName, new Date(), ->
                    J.ReactivesQueue.update recalcItem._id, $set: status: "done"
