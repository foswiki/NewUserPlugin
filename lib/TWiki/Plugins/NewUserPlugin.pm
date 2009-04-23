# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2009 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# For licensing info read LICENSE file in the Foswiki root.

###############################################################################
package TWiki::Plugins::NewUserPlugin;

use strict;
use vars qw( $VERSION $RELEASE $SHORTDESCRIPTION $NO_PREFS_IN_TOPIC $done);

use constant DEBUG => 0; # toggle me

$VERSION = '$Rev$';
$RELEASE = 'v1.20';
$SHORTDESCRIPTION = 'Create a user topic if it does not exist yet';
$NO_PREFS_IN_TOPIC = 1;

###############################################################################
sub writeDebug {
  return unless DEBUG;
  print STDERR 'NewUserPlugin - '.$_[0]."\n";
  #TWiki::Func::writeDebug("NewUserPlugin - $_[0]");
}

###############################################################################
sub writeWarning {
  writeDebug('WARNING: '.$_[0]);
  TWiki::Func::writeWarning("NewUserPlugin - ".$_[0]);
}

###############################################################################
sub initPlugin {
#  my ($topic, $web, $user) = @_;

  $done = 0;
  return 1;
}

###############################################################################
# unfortunately we can't use the initializeUserHandler as the engine is not
# fully initialized then. even the beforeCommonTagsHandler get's called in
# a half-init state in the middle of the main constructor. so we have to wait for
# the main object to be fully initialized, i.e. its i18n subsystem
sub beforeCommonTagsHandler {
  return if !defined($TWiki::Plugins::SESSION->{i18n}) || $done;
  $done = 1;

  #writeDebug("called beforeCommonTagsHandler");

  my $wikiName = TWiki::Func::getWikiName();
  my $usersWeb = $TWiki::cfg{UsersWebname};
  return if TWiki::Func::topicExists($usersWeb, $wikiName);

  # SMELL: hack to prevent creation homepages for unknown user
  # we can't ask the engine if the user exists when the user is authenticated
  # externally as it assumes that any successfully authenticated user
  # does in some way exist ... which it doesn't in our definition, i.e.
  # if we don't get a proper WikiName; besides, the engine can't cope
  # with topics starting with a lowercase letter anyway
  my $wikiWordRegex = TWiki::Func::getRegularExpression('wikiWordRegex');
  unless ($wikiName =~ /^($wikiWordRegex)$/) {
    writeDebug("user's wikiname '$wikiName' is not a WikiWord ... not creating a homepage");
    return;
  }

  writeDebug("creating homepage for user $wikiName");
  createUserTopic($wikiName)
}

###############################################################################
sub expandVariables {
  my ($text, $topic, $web) = @_;

  return '' unless $text;

  $text =~ s/^\"(.*)\"$/$1/go;

  my $found = 0;
  my $mixedAlphaNum = TWiki::Func::getRegularExpression('mixedAlphaNum');

  $found = 1 if $text =~ s/\$percnt/\%/go;
  $found = 1 if $text =~ s/\$nop//go;
  $found = 1 if $text =~ s/\$n([^$mixedAlphaNum]|$)/\n$1/go;
  $found = 1 if $text =~ s/\$dollar/\$/go;

  $text = TWiki::Func::expandCommonVariables($text, $topic, $web) if $found;

  return $text;
}

###############################################################################
# creates a user topic for the given wikiUserName
sub createUserTopic {
  my $wikiUserName = shift;

  my $systemWeb = $TWiki::cfg{SystemWebName};
  my $usersWeb = $TWiki::cfg{UsersWebName};
  my $newUserTemplate =
    TWiki::Func::getPreferencesValue('NEWUSERTEMPLATE') || 'NewUserTemplate';
  my $tmplTopic;
  my $tmplWeb;

  # search the NEWUSERTEMPLATE
  $newUserTemplate =~ s/^\s+//go;
  $newUserTemplate =~ s/\s+$//go;
  $newUserTemplate =~ s/\%TWIKIWEB\%/$systemWeb/g;
  $newUserTemplate =~ s/\%SYSTEMWEB\%/$systemWeb/g;
  $newUserTemplate =~ s/\%MAINWEB\%/$usersWeb/g;

  # in Main
  ($tmplWeb, $tmplTopic) =
    TWiki::Func::normalizeWebTopicName($usersWeb, $newUserTemplate);

  unless (TWiki::Func::topicExists($tmplWeb, $tmplTopic)) {

    # in TWiki
    ($tmplWeb, $tmplTopic) =
      TWiki::Func::normalizeWebTopicName($systemWeb, $newUserTemplate);

    unless (TWiki::Func::topicExists($tmplWeb, $tmplTopic)) {
      writeWarning("no new user template found"); # not found
      return;
    }
  }

  writeDebug("newusertemplate = $tmplWeb.$tmplTopic");

  # read the template
  my $text = TWiki::Func::readTopicText($tmplWeb, $tmplTopic);
  unless ($text) {
    writeWarning("can't read $tmplWeb.$tmplTopic");
    return;
  }

  # insert data
  my $wikiName = TWiki::Func::getWikiName();
  my $loginName = TWiki::Func::wikiToUserName($wikiName);
  $text =~ s/\$nop//go; 
  $text =~ s/\%WIKINAME\%/$wikiName/go;
  $text =~ s/\%USERNAME\%/$loginName/go;
  $text =~ s/\%WIKIUSERNAME\%/$wikiUserName/go;

  writeDebug("saving new home topic $usersWeb.$wikiName");
  my $errorMsg = TWiki::Func::saveTopicText($usersWeb, $wikiName, $text);
  if ($errorMsg) {
    writeWarning("error during save of $tmplWeb.$tmplTopic: $errorMsg");
    return;
  } 

  # expanding VARs in a second phase, after the topic file was created (to get correct $meta objects)
  my $found = 0;
  $found = 1 if $text =~ s/\%EXPAND\{(.*?)\}\%/&expandVariables($1, $wikiName, $usersWeb)/ge;
  $found = 1 if $text =~ s/\%STARTEXPAND\%(.*?)\%STOPEXPAND\%/TWiki::Func::expandCommonVariables($1, $wikiName, $usersWeb)/ges;

  if ($found) {
    writeDebug("expanding vars in new home topic $usersWeb.$wikiName");
    $errorMsg = TWiki::Func::saveTopicText($usersWeb, $wikiName, $text);
    if ($errorMsg) {
      writeWarning("error during save of var expanded version of $usersWeb.$wikiName: $errorMsg");
    }
  }
}

1;
