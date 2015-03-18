Controller = require 'members-area/app/controller'

module.exports = class Timecounts extends Controller
  @before 'ensureAdmin', only: ['settings']
  @before 'loadRoles', only: ['settings']
  @before 'handleSettings', only: ['settings']
  @before 'doLogin', only: ['settings']
  @before 'doSync', only: ['settings']

  settings: ->

  handleSettings: (done) ->
    @data.endpoint ?= @plugin.endpoint()
    @data.roleId ?= @plugin.get('roleId') ? 1
    @data.apiToken ?= @plugin.get('apiToken')
    @data.organizationSlug ?= @plugin.get('organizationSlug')

    if @req.method is 'POST' and @req.body.saveSettings is 'true'
      @plugin.set {endpoint: @data.endpoint, apiToken: @data.apiToken, roleId: @data.roleId, organizationSlug: @data.organizationSlug}

    done()

  loadRoles: (done) ->
    @req.models.Role.find (err, @roles) =>
      done(err)

  ensureAdmin: (done) ->
    return @redirectTo "/login?next=#{encodeURIComponent @req.path}" unless @req.user?
    return done new @req.HTTPError 403, "Permission denied" unless @req.user.can('admin')
    done()

  doLogin: (done) ->
    return done() unless @req.body.login
    if @req.body.login is 'login'
      # Attempt to login
      data =
        email: @data.email
        password: @data.password
        expires_after: 30*60
      @plugin.timecounts.post "/users/sign_in", data, (err, response) =>
        if err
          if err.status is 401
            @loginError = "Incorrect username or password"
          else
            @loginError = "Something went wrong"
          return done()
        @loginStep2 = true
        @organizations = {}
        @organizations["#{org.id}-#{org.slug}"] = org.name for org in response.data.user.admin_organizations
        return done()
    else
      # Step 2
      [id, slug...] = @data.organization.split("-")
      id = parseInt(id, 10)
      slug = slug.join("-")
      data =
        email: @data.email
        password: @data.password
        scopes: ['read:person', 'write:person', 'read:group', 'write:group']
        organization_ids: [id]
      @plugin.timecounts.post "/users/sign_in", data, (err, response) =>
        if err
          if err.status is 401
            @loginError = "Incorrect username or password"
          else
            @loginError = "Something went wrong"
          return done()
        @plugin.set {apiToken: response.data.token, organizationSlug: slug}
        @data.apiToken = @plugin.get('apiToken')
        @data.organizationSlug = @plugin.get('organizationSlug')
        return done()

  doSync: (done) ->
    return done() unless @req.body.sync
    @plugin.async.series
      checkExistingTimecountsGroups: (done) =>
        rolesByTimecountsGroupId = {}
        rolesByTimecountsGroupId[role.meta.timecountsId] = role for role in @roles when role.meta?.timecountsId?
        groupIds = Object.keys(rolesByTimecountsGroupId)
        return done() if groupIds.length is 0
        # Check these still exist on timecounts
        @plugin.timecounts.get "/organizations/#{@plugin.get('organizationSlug')}/groups?id_in=#{groupIds.join(",")}", (err, response) =>
          return done(new Error("Failed to fetch groups from timecounts.")) if err
          timecountsGroups = response.data
          timecountsGroupsById = {}
          timecountsGroupsById[group.id] = group for group in timecountsGroups
          @plugin.async.eachSeries groupIds, (groupId, done) =>
            if !timecountsGroupsById[groupId]
              # Timecounts can't find this group, it must have been deleted!
              role = rolesByTimecountsGroupId[groupId]
              role.setMeta timecountsId: undefined
              delete rolesByTimecountsGroupId[groupId]
              role.save done
            else
              done()
          , done

      createTimecountsGroups: (done) =>
        groupFromRole = (role) ->
          name: role.name
        create = (role, done) =>
          return done() if role.meta?.timecountsId
          groupData = groupFromRole(role)
          @plugin.timecounts.post "/organizations/#{@plugin.get('organizationSlug')}/groups", groupData, (err, response) =>
            next = (err, response) =>
              return done(new Error("Failed to create group in timecounts.")) if err
              group = response.data
              if Array.isArray(group)
                group = group[0]
              role.setMeta timecountsId: group.id
              role.save done
            if err and err.status is 422
              @plugin.timecounts.get "/organizations/#{@plugin.get('organizationSlug')}/groups?name=#{encodeURIComponent groupData.name}", next
            else
              next(err, response)
        @plugin.async.mapSeries @roles, create, done

      loadUsers: (done) =>
        requiredRoleId = @plugin.get('roleId')
        @req.models.User.find()
        .where("EXISTS(SELECT 1 FROM role_user WHERE user_id = user.id AND approved IS NOT NULL AND rejected IS NULL AND role_id = ?)", [requiredRoleId])
        .all (err, @users) =>
          done(err)

      createUsers: (done) =>
        allUsers = @users[..]
        batches = []
        while allUsers.length > 0
          batches.push allUsers.splice(0, 25)

        return done() unless batches.length

        processBatch = (users, done) =>
          @plugin.async.series
            checkExistingTimecountsUsers: (done) =>
              usersByTimecountsPersonId = {}
              usersByTimecountsPersonId[user.meta.timecountsId] = user for user in users when user.meta?.timecountsId?
              personIds = Object.keys(usersByTimecountsPersonId)
              return done() if personIds.length is 0
              # Check these people still exist on tiemcounts
              @plugin.timecounts.get "/organizations/#{@plugin.get('organizationSlug')}/people?id_in=#{personIds.join(",")}", (err, response) =>
                return done(new Error("Failed to fetch people from timecounts.")) if err
                timecountsPeople = response.data
                timecountsPeopleById = {}
                timecountsPeopleById[person.id] = person for person in timecountsPeople
                @plugin.async.eachSeries personIds, (personId, done) =>
                  if !timecountsPeople[personId]
                    # Timecounts can't find this person, must have been deleted
                    user = usersByTimecountsPersonId[personId]
                    user.setMeta timecountsId: undefined
                    delete usersByTimecountsPersonId[personId]
                    user.save done
                  else
                    done()
                , done

            createTimecountsUsers: (done) =>
              addressPartsFromAddress = (address) ->
                # Ripped from https://github.com/members-area/members-area-gocardless/blob/1981ca320b2c2b3209ed65450372a1119b9a7461/index.coffee#L253-270
                # Sorry this is a bit Southampton specific, pull requests welcome
                if address?.length
                  tmp = address.match /[A-Z]{2}[0-9]{1,2}\s*[0-9][A-Z]{2}/i
                  if tmp
                    postcode = tmp[0].toUpperCase()
                    address = address.replace(tmp[0], "")
                  tmp = address.split /[\n\r,]/
                  tmp = tmp.filter (a) -> a.replace(/\s+/g, "").length > 0
                  tmp = tmp.filter (a) -> !a.match /^(hants|hampshire)$/
                  for potentialTown, i in tmp
                    t = potentialTown.replace /[^a-z]/gi, ""
                    if t.match /^(southampton|soton|eastleigh|chandlersford|winchester|northbaddesley|havant|portsmouth|bournemouth|poole|bognorregis|romsey|lyndhurst|eye|warsash|lymington)$/i
                      town = potentialTown
                      tmp.splice i, 1
                      break
                  if tmp.length > 1
                    address2 = tmp.pop()
                  address1 = tmp.join(", ")
                if town?
                  return {
                    address: address1
                    city: town
                    province: "Hampshire"
                    country: "UK"
                    zipcode: postcode
                  }
                else
                  # Use postcode to look up address?
                  return {}

              personFromUser = (user) ->
                base = addressPartsFromAddress(user.address)
                base.email = user.email.toLowerCase()
                base.name = user.fullname # Timecounts splits this up for us.
                return base

              create = (user, done) =>
                return done() if user.meta?.timecountsId
                personData = personFromUser(user)
                @plugin.timecounts.post "/organizations/#{@plugin.get('organizationSlug')}/people", personData, (err, response) =>
                  next = (err, response) =>
                    return done(new Error("Failed to create person in timecounts.")) if err
                    person = response.data
                    if Array.isArray(person)
                      person = person[0]
                    user.setMeta timecountsId: person.id
                    user.save -> done() # ignore errors
                  if err and err.status is 422
                    @plugin.timecounts.get "/organizations/#{@plugin.get('organizationSlug')}/people?email=#{encodeURIComponent personData.email}", next
                  else
                    next(err, response)
              @plugin.async.mapSeries users, create, done
          , done

        @plugin.async.eachSeries batches, processBatch, done

      assignToGroups: (done) =>
        updateGroupWithRole = (role, done) =>
          groupId = role.meta?.timecountsId
          return done() unless groupId
          # Find the people that have this role
          @req.models.User.find()
            .where("EXISTS(SELECT 1 FROM role_user WHERE user_id = user.id AND approved IS NOT NULL AND rejected IS NULL AND role_id = ?)", [role.id])
            .all (err, users) =>
              return done(err) if err
              return done() unless users?.length
              personIds = (user.meta.timecountsId for user in users when user.meta?.timecountsId?)
              @plugin.timecounts.put "/organizations/#{@plugin.get('organizationSlug')}/groups/#{groupId}/members", personIds, (err, response) =>
                return done() unless err
                return done(new Error(err.data?.error_message ? "Something went wrong"))
        @plugin.async.each @roles, updateGroupWithRole, done


    , done
