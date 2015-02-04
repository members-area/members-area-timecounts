members-area-timecounts
=======================

This plugin synchronizes contacts and roles from the Members Area into
timecounts.org

Status
------

You can login to Timecounts easily and select an organization to sync
to.

Simple syncing works.

Full syncing does not yet exist.

There's no progress reporting so you just have to wait for sync to
finish and trust it's working.

There's very little in the way of error handling.

Simple syncing
--------------

Simple syncing will create people in Timecounts based on users in the
Members Area if they don't already exist. If they do exist it will NOT
update the people in Timecounts. No information from Timecounts will be
copied back into the Members Area.

One tag (group) will be created named after each role within the members
area (or an existing tag will be hijacked) and on sync the tag will
contain only the people in the members area that have that tag.

Full syncing
------------

In the long run we should consider supporting a fuller sync, whereby
differences in data between the Members Area and Timecounts asks the
admin to reconcile (e.g. if a user changes address, email, name, etc).
