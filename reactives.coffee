J.ReactivesQueue = new Mongo.Collection "jframework_reactives"
J.ReactivesQueue._ensureIndex priority: -1

unless Meteor.settings.public.isMainMeteor
    Meteor.startup ->
        J.ReactivesQueue.find({ status: "new" }, { sort: { priority: -1 } }).observe
            added: (recalcItem) ->
                console.log recalcItem.mName
                J.models[recalcItem.mName].collection._collection.rawCollection.update recalcItem.mId, $set: { status: "inProgress" }
                instance = J.models[recalcItem.mName].find recalcItem.mId
                J.denorm.recalc instance, recalcItem.rName, new Date(), ->
                    J.models[recalcItem.mName].update recalcItem.mId, $set: { status: "done" }
