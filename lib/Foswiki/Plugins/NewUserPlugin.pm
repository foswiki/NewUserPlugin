# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2013 Michael Daum http://michaeldaumconsulting.com
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
package Foswiki::Plugins::NewUserPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Error qw(:try);

our $VERSION = '2.41';
our $RELEASE = '2.41';
our $SHORTDESCRIPTION = 'Create a user topic if it does not exist yet';
our $NO_PREFS_IN_TOPIC = 1;
our $done;

use constant DEBUG => 0; # toggle me

###############################################################################
sub initPlugin {
#  my ($topic, $web, $user) = @_;

  Foswiki::Func::registerRESTHandler('createUserTopics', \&restCreateUserTopics, 
    authenticate => 0
  );

  $done = 0;
  return 1;
}

###############################################################################
sub writeDebug {
  return unless DEBUG;
  print STDERR 'NewUserPlugin - '.$_[0]."\n";
  #Foswiki::Func::writeDebug("NewUserPlugin - $_[0]");
}

###############################################################################
sub writeWarning {
  writeDebug('WARNING: '.$_[0]);
  Foswiki::Func::writeWarning("NewUserPlugin - ".$_[0]);
}

###############################################################################
sub restCreateUserTopics {
  my $session = shift;

  my $mapping = $session->{users}{mapping};
  my $passwordManager = $mapping->{passwords};

  if ($passwordManager->canFetchUsers) {
    my $usersWeb = $Foswiki::cfg{UsersWebName};
    my $wikiWordRegex = $Foswiki::regex{'wikiWordRegex'};
    my $it = $passwordManager->fetchUsers();
    my $count = 0;
    while ($it->hasNext()) {
      my $loginName = $it->next();
      my $wikiName = Foswiki::Func::userToWikiName($loginName, 1);
      #writeDebug("checking loginName=$loginName, wikiName=$wikiName");
      next if Foswiki::Func::topicExists($usersWeb, $wikiName);
      unless ($wikiName =~ /^($wikiWordRegex)$/) {
	writeDebug("user's wikiname '$wikiName' is not a WikiWord ... not creating a user topic");
	next;
      }
      writeDebug("creating a user topic for $wikiName");
      createUserTopic($wikiName);
      $count++;
    }

    writeDebug("created $count user topics");
  } else {
    writeWarning("can't fetch users");
  }

  return;
}

###############################################################################
# unfortunately we can't use the initializeUserHandler as the engine is not
# fully initialized then. even the beforeCommonTagsHandler get's called in
# a half-init state in the middle of the main constructor. so we have to wait for
# the main object to be fully initialized, i.e. its i18n subsystem
sub beforeCommonTagsHandler {
  return if !defined($Foswiki::Plugins::SESSION->{i18n}) || $done;
  $done = 1;

  #writeDebug("called beforeCommonTagsHandler");

  my $wikiName = Foswiki::Func::getWikiName();
  my $usersWeb = $Foswiki::cfg{UsersWebName};
  return if Foswiki::Func::topicExists($usersWeb, $wikiName);

  # SMELL: hack to prevent creation homepages for unknown user
  # we can't ask the engine if the user exists when the user is authenticated
  # externally as it assumes that any successfully authenticated user
  # does in some way exist ... which it doesn't in our definition, i.e.
  # if we don't get a proper WikiName; besides, the engine can't cope
  # with topics starting with a lowercase letter anyway
  my $wikiWordRegex = $Foswiki::regex{'wikiWordRegex'};
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
  my $mixedAlphaNum = $Foswiki::regex{'mixedAlphaNum'};

  $found = 1 if $text =~ s/\$perce?nt/\%/go;
  $found = 1 if $text =~ s/\$nop//go;
  $found = 1 if $text =~ s/\$n([^$mixedAlphaNum]|$)/\n$1/go;
  $found = 1 if $text =~ s/\$dollar/\$/go;

  $text = Foswiki::Func::expandCommonVariables($text, $topic, $web) if $found;

  return $text;
}

###############################################################################
# creates a user topic for the given wikiName
sub createUserTopic {
  my $wikiName = shift;

  my $systemWeb = $Foswiki::cfg{SystemWebName};
  my $usersWeb = $Foswiki::cfg{UsersWebName};
  my $newUserTemplate =
    $Foswiki::cfg{NewUserPlugin}{NewUserTemplate} ||
    Foswiki::Func::getPreferencesValue('NEWUSERTEMPLATE') || 'NewUserTemplate';
  my $tmplTopic;
  my $tmplWeb;
  my $wikiUserName = $usersWeb.'.'.$wikiName;

  # search the NEWUSERTEMPLATE
  $newUserTemplate =~ s/^\s+//go;
  $newUserTemplate =~ s/\s+$//go;
  $newUserTemplate =~ s/\%SYSTEMWEB\%/$systemWeb/g;
  $newUserTemplate =~ s/\%MAINWEB\%/$usersWeb/g;

  # in users web
  ($tmplWeb, $tmplTopic) =
    Foswiki::Func::normalizeWebTopicName($usersWeb, $newUserTemplate);

  unless (Foswiki::Func::topicExists($tmplWeb, $tmplTopic)) {

    ($tmplWeb, $tmplTopic) =
      Foswiki::Func::normalizeWebTopicName($systemWeb, $newUserTemplate);

    unless (Foswiki::Func::topicExists($tmplWeb, $tmplTopic)) {
      writeWarning("no new user template found"); # not found
      return;
    }
  }

  #writeDebug("newusertemplate = $tmplWeb.$tmplTopic");

  # read the template
  my ($meta, $text) = Foswiki::Func::readTopic($tmplWeb, $tmplTopic);
  unless ($meta) {
    writeWarning("can't read $tmplWeb.$tmplTopic");
    return;
  }

  # insert data
  my $loginName = Foswiki::Func::wikiToUserName($wikiName);
  $text =~ s/\$nop//go; 
  $text =~ s/\%USERNAME\%/$loginName/go;
  $text =~ s/\%WIKINAME\%/$wikiName/go;
  $text =~ s/\%WIKIUSERNAME\%/$wikiUserName/go;
  $text =~ s/\%EXPAND\{(.*?)\}\%/expandVariables($1, $wikiName, $usersWeb)/ge;
  $text =~ s/\%STARTEXPAND\%(.*?)\%STOPEXPAND\%/Foswiki::Func::expandCommonVariables($1, $wikiName, $usersWeb)/ges;

  foreach my $field ($meta->find('FIELD'), $meta->find('PREFERENCE')) {
    $field->{value} =~ s/\%USERNAME\%/$loginName/go;
    $field->{value} =~ s/\%WIKINAME\%/$wikiName/go;
    $field->{value} =~ s/\%WIKIUSERNAME\%/$wikiUserName/go;
    $field->{value} =~ s/\%EXPAND\{(.*?)\}\%/expandVariables($1, $wikiName, $usersWeb)/ge;
    $field->{value} =~ s/\%STARTEXPAND\%(.*?)\%STOPEXPAND\%/Foswiki::Func::expandCommonVariables($1, $wikiName, $usersWeb)/ges;
  }

  #writeDebug("patching in RegistrationAgent");

  my $session = $Foswiki::Plugins::SESSION;
  my $origCUID = $session->{user};
  my $registrationAgentCUID = 
    Foswiki::Func::getCanonicalUserID($Foswiki::cfg{Register}{RegistrationAgentWikiName});
  #writeDebug("registrationAgentCUID=$registrationAgentCUID");

  $session->{user} = $registrationAgentCUID;
  #writeDebug("saving new user topic $usersWeb.$wikiName");
  
  try {
    Foswiki::Func::saveTopic($usersWeb, $wikiName, $meta, $text);
  } catch Error::Simple with {
    writeWarning("error during save of $usersWeb.$wikiName: " . shift);
  };

  $session->{user} = $origCUID;
}

1;
