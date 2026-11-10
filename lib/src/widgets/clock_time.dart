import 'package:flutter/material.dart';

/// A local time of day as the app writes it: "3:03 pm", not "3:03 PM". The
/// period reads as part of the time, in the chat list and in a conversation.
String clockTime(DateTime at, MaterialLocalizations localizations) =>
    localizations
        .formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal()))
        .toLowerCase();
