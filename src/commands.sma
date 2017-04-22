/**
 * TODO: Add top-level comment
 */

#define VERSION_STRING "1.0.0"
//#define COMPILE_FOR_DEBUG

#define MAX_NUM_PREFIXES 8
#define INITIAL_COMMANDS_SIZE 8
#define INITIAL_ALIASES_SIZE 16
#define PRINT_BUFFER_LENGTH 191

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <logger>

#include "include/commands/alias_t.inc"
#include "include/commands/command_t.inc"
#include "include/commands/commands_const.inc"

#include "include/stocks/exception_stocks.inc"
#include "include/stocks/flag_stocks.inc"
#include "include/stocks/param_stocks.inc"
#include "include/stocks/misc_stocks.inc"
#include "include/stocks/string_stocks.inc"

stock Command: toCommand(value)                    return Command:(value);
stock Command: operator= (value)                   return toCommand(value);
stock          operator- (Command: command, other) return any:(command) -  other;
stock bool:    operator==(Command: command, other) return any:(command) == other;
stock bool:    operator!=(Command: command, other) return any:(command) != other;
stock bool:    operator< (Command: command, other) return any:(command) <  other;
stock bool:    operator<=(Command: command, other) return any:(command) <= other;
stock bool:    operator> (Command: command, other) return any:(command) >  other;
stock bool:    operator>=(Command: command, other) return any:(command) >= other;

stock Alias: toAlias(value)                  return Alias:(value);
stock Alias: operator= (value)               return toAlias(value);
stock        operator- (Alias: alias, other) return any:(alias) -  other;
stock bool:  operator==(Alias: alias, other) return any:(alias) == other;
stock bool:  operator!=(Alias: alias, other) return any:(alias) != other;
stock bool:  operator< (Alias: alias, other) return any:(alias) <  other;
stock bool:  operator<=(Alias: alias, other) return any:(alias) <= other;
stock bool:  operator> (Alias: alias, other) return any:(alias) >  other;
stock bool:  operator>=(Alias: alias, other) return any:(alias) >= other;

static const CMD_TEAM_KEYS[CsTeams][] = {
  "CMD_UNASSIGNED",
  "CMD_TERRORISTS",
  "CMD_CTS",
  "CMD_SPECTATORS"
};

enum Forwards {
  fwReturn = 0,
  onBeforeCommand,
  onCommand,
  onCommandRegistered,
  onPrefixesChanged,
  onRegisterCommands
};

static g_fw[Forwards] = {
  0,
  INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE
};

static Array: g_commandsList, g_numCommands;
static g_tempCommand[command_t], Command: g_Command = Invalid_Command;

static Array: g_aliasesList, g_numAliases;
static g_tempAlias[alias_t], Alias: g_Alias = Invalid_Alias;

static Trie: g_aliasesMap;
static Trie: g_prefixesMap;

static g_szCommandBuffer[PRINT_BUFFER_LENGTH + 1];

static g_szError[PRINT_BUFFER_LENGTH + 1];
static bool: isOnBeforeCommand;

static g_pCvar_Prefixes;

public plugin_precache() {
#if defined COMPILE_FOR_DEBUG
  LoggerSetVerbosity(This_Logger, Severity_Lowest);
#endif
}

public plugin_natives() {
  register_library("commands");

  register_native("cmd_setError", "native_setError", 0);

  register_native("cmd_registerCommand", "native_registerCommand", 0);
  register_native("cmd_registerAlias", "native_registerAlias", 0);

  register_native("cmd_findCommand", "native_findCommand", 0);

  register_native("cmd_isValidCommand", "native_isValidCommand", 0);
  register_native("cmd_isValidAlias", "native_isValidAlias", 0);

  register_native("cmd_getNumCommands", "native_getNumCommands", 0);
  register_native("cmd_getNumAliases", "native_getNumAliases", 0);
}

public plugin_init() {
  new buildId[32];
  getBuildId(buildId);
  register_plugin("Command Manager", buildId, "Tirant");

  create_cvar("command_manager_version", buildId, FCVAR_SPONLY,
              "The current version of Command Manager being used");
  
  registerConCmds();
  createForwards();

  g_pCvar_Prefixes = create_cvar("command_prefixes", "/.!", FCVAR_SERVER|FCVAR_SPONLY,
                                 "List of all symbols that can preceed commands");
  hook_cvar_change(g_pCvar_Prefixes, "onPrefixesAltered");

  new prefixes[MAX_NUM_PREFIXES];
  get_pcvar_string(g_pCvar_Prefixes, prefixes, charsmax(prefixes));
  onPrefixesAltered(g_pCvar_Prefixes, NULL_STRING, prefixes);

  register_clcmd("say", "onSay");
  register_clcmd("say_team", "onSayTeam");
}

stock getBuildId(buildId[], len = sizeof buildId) {
  #if defined COMPILE_FOR_DEBUG
  return formatex(buildId, len - 1, "%s [%s] [DEBUG]", VERSION_STRING, __DATE__);
#else
  return formatex(buildId, len - 1, "%s [%s]", VERSION_STRING, __DATE__);
#endif
}

registerConCmds() {
  new prefix[] = "cmd";
  registerConCmd(
      .prefix = prefix,
      .command = "list,cmds,commands",
      .callback = "onPrintCommands",
      .desc = "Prints the list of commands with their details");

  registerConCmd(
      .prefix = prefix,
      .command = "aliases",
      .callback = "onPrintAliases",
      .desc = "Prints the list of aliases with their details");
}

createForwards() {
  createOnBeforeCommand();
  createOnCommand();
}

createOnBeforeCommand() {
  LoggerLogDebug("Creating forward cmd_onBeforeCommand");
  g_fw[onBeforeCommand] = CreateMultiForward(
      "cmd_onBeforeCommand", ET_STOP,
      FP_CELL, FP_CELL, FP_CELL);
  LoggerLogDebug("g_fw[onBeforeCommand] = %d", g_fw[onBeforeCommand]);
}

createOnCommand() {
  LoggerLogDebug("Creating forward cmd_onCommand");
  g_fw[onCommand] = CreateMultiForward(
      "cmd_onCommand", ET_IGNORE,
      FP_CELL, FP_CELL, FP_CELL);
  LoggerLogDebug("g_fw[onCommand] = %d", g_fw[onCommand]);
}

public onPrefixesAltered(pCvar, const oldValue[], const newValue[]) {
  assert pCvar == g_pCvar_Prefixes;
  if (g_prefixesMap == Invalid_Trie) {
    g_prefixesMap = TrieCreate();
    LoggerLogDebug("Created g_prefixesMap = Trie: %d", g_prefixesMap);
  } else {
    TrieClear(g_prefixesMap);
    LoggerLogDebug("Cleared g_prefixesMap");
  }

  LoggerLogDebug("Updating command prefixes table to: \"%s\"", newValue);

  new i = 0;
  new ch;
  new temp[2];
  while (newValue[i] != EOS) {
      ch = newValue[i];
      temp[0] = ch;
      TrieSetCell(g_prefixesMap, temp, ch);
      i++;
  }

  if (g_fw[onPrefixesChanged] == INVALID_HANDLE) {
      LoggerLogDebug("Creating forward cmd_onPrefixesChanged");
      g_fw[onPrefixesChanged] = CreateMultiForward(
          "cmd_onPrefixesChanged", ET_IGNORE,
          FP_STRING, FP_STRING);
      LoggerLogDebug("g_fw[onPrefixesChanged] = %d", g_fw[onPrefixesChanged]);
  }

  ExecuteForward(g_fw[onPrefixesChanged], g_fw[fwReturn], oldValue, newValue);
}

public onSay(id) {
  read_args(g_szCommandBuffer, PRINT_BUFFER_LENGTH);
  return checkCommandAndHandle(id, false, g_szCommandBuffer, PRINT_BUFFER_LENGTH);
}

public onSayTeam(id) {
  read_args(g_szCommandBuffer, PRINT_BUFFER_LENGTH);
  return checkCommandAndHandle(id, true, g_szCommandBuffer, PRINT_BUFFER_LENGTH);
}

/**
 * Checks if a command is used with a correct prefix and triggers it if it is.
 * 
 * @param id          The player who entered the command
 * @param teamCommand {@code true} if it was sent via team only chat,
 *                      {@code false} otherwise
 * @param args        Message args being sent
 * @param len         The max number of bytes in {@param args}, i.e.,
 *                      {@code sizeof args - 1}
 * 
 * @return {@code PLUGIN_CONTINUE} in the event that this was not a command
 *         or did not use a valid prefix, otherwise {@code PLUGIN_CONTINUE}
 *         or {@code PLUGIN_HANDLED} depending on whether or not the command
 *         should be hidden or not from the chat area
 */
checkCommandAndHandle(
    const id,
    const bool: teamCommand,
    args[], const len) {
  strtolower(args);
  remove_quotes(args);

  new temp[2], prefix;
  temp[0] = args[0];
  if (!TrieGetCell(g_prefixesMap, temp, prefix)) {
    return PLUGIN_CONTINUE;
  }

  // Breaks the message into alias and args
  new alias[alias_String_length+1];
  argbreak(args[1], alias, charsmax(alias), args, len);

  new Alias: aliasId;
  if (TrieGetCell(g_aliasesMap, alias, aliasId)) {
    loadAlias(aliasId);
    LoggerLogDebug("Alias found: %d (\"%s\") is bound to command %d",
        aliasId, g_tempAlias[alias_String], g_tempAlias[alias_Command]);
    return tryExecutingCommand(
        prefix, g_tempAlias[alias_Command], id, teamCommand, args, len);
  }

  return PLUGIN_CONTINUE;
}

/**
 * Attempts to execute the given command for a specified player if their current
 * state meets the criteria that the command requires, and the command is not 
 * blocked by another plugin.
 *
 * @param prefix      The prefix used when executing command
 * @param command     The command to try and execute
 * @param id          The player who is executing the command
 * @param teamCommand {@code true} if it was sent via team only chat,
 *                      {@code false} otherwise
 * @param args        Additional arguments passed with the command (e.g.,
 *                    {@code /kill <player>}, where the value of
 *                    {@code <player>} would be this parameter)
 * @param len         The max number of bytes in {@param args}, i.e.,
 *                      {@code sizeof args - 1}
 */
tryExecutingCommand(
    const prefix,
    const Command: command,
    const id,
    const bool: isTeamCommand,
    args[], const len) {
  #pragma unused len
  assert isValidCommand(command);
  assert isValidId(id);

  loadCommand(command);

  new const bool: hasAccess = bool:(access(id, g_tempCommand[command_AdminFlags]));
  if (!hasAccess) {
    cmd_printColor(id, "%L", id, "CMD_NO_ACCESS");
    return PLUGIN_HANDLED;
  }

  new const flags = g_tempCommand[command_Flags];
  if (!areFlagsSet(This_Logger, flags, FLAG_METHOD_SAY, FLAG_METHOD_SAY_TEAM)) {
    return PLUGIN_CONTINUE;
  } else {
    switch (getXorFlag(This_Logger, flags, FLAG_METHOD_SAY, FLAG_METHOD_SAY_TEAM)) {
      case FLAG_METHOD_SAY:
          if (isTeamCommand) {
            cmd_printColor(id, "%L", id, "CMD_SAYTEAM_ONLY");
            return PLUGIN_HANDLED;
          }
      case FLAG_METHOD_SAY_TEAM:
          if (!isTeamCommand) {
            cmd_printColor(id, "%L", id, "CMD_SAYALL_ONLY");
            return PLUGIN_HANDLED;
          }
    }
  }

  if (!areFlagsSet(This_Logger, flags, FLAG_STATE_ALIVE, FLAG_STATE_DEAD)) {
    return PLUGIN_CONTINUE;
  } else {
    new const bool: isAlive = bool:(is_user_alive(id));
    switch (getXorFlag(This_Logger, flags, FLAG_STATE_ALIVE, FLAG_STATE_DEAD)) {
      case FLAG_STATE_ALIVE:
          if (!isAlive) {
            cmd_printColor(id, "%L", id, "CMD_DEAD_ONLY");
            return PLUGIN_HANDLED;
          }
      case FLAG_STATE_DEAD:
          if (isAlive) {
            cmd_printColor(id, "%L", id, "CMD_ALIVE_ONLY");
            return PLUGIN_HANDLED;
          }
    }
  }

  new const CsTeams: team = CsTeams:(get_user_team(id));
  new const teamFlag = getFlagForTeam(team);
  if (!isFlagSet(flags, teamFlag)) {
    buildValidTeamsMessage(id, g_szError, charsmax(g_szError), teamFlag, flags);
    cmd_printColor(id, g_szError);
    return PLUGIN_HANDLED;
  }

  g_szError[0] = EOS;
  isOnBeforeCommand = true;
  ExecuteForward(g_fw[onBeforeCommand], g_fw[fwReturn], id, prefix, command);
  isOnBeforeCommand = false;
  if (g_fw[fwReturn] == PLUGIN_HANDLED) {
    if (isStringEmpty(g_szError)) {
      cmd_printColor(id, "%L", id, "CMD_BLOCKED");
      LoggerLogWarn("A command was blocked without giving a reason why.");
    } else {
      cmd_printColor(id, g_szError);
    }

    return PLUGIN_HANDLED;
  }

  new name[32];
  argparse(args, 0, name, charsmax(name));
  //argbreak(args[1], name, charsmax(name), args, len);

  new const player = cmd_target(id, name, CMDTARGET_ALLOW_SELF);
  callfunc_begin_i(g_tempCommand[command_FuncID], g_tempCommand[command_PluginID]); {
    callfunc_push_int(id);
    callfunc_push_int(player);
    callfunc_push_str(args, false);
  } callfunc_end();

  ExecuteForward(g_fw[onCommand], g_fw[fwReturn], id, prefix, command);
  return PLUGIN_HANDLED;
}

stock cmd_printColor(const id, const message[], any: ...) {
  static buffer[PRINT_BUFFER_LENGTH+1];
  static offset;
  if (buffer[0] == EOS) {
    offset = formatex(buffer, PRINT_BUFFER_LENGTH,
        "%L ", id, "CMD_PRINT_COLOR_HEADER", id, "CMD_NAME_SHORT");
  }

  new length = offset;
  switch (numargs()) {
    case 2: length += copy(buffer[offset], PRINT_BUFFER_LENGTH - offset, message);
    default: length += vformat(buffer[offset], PRINT_BUFFER_LENGTH - offset, message, 3);
  }

  buffer[length] = EOS;
  client_print_color(id, print_team_default, buffer);
}

stock buildValidTeamsMessage(id, dst[], const len, const teamFlag, const flags) {
  new CsTeams: team;
  new list[64], listLen;
  for (new i = FLAG_TEAM_UNASSIGNED; i <= FLAG_TEAM_SPECTATOR; i++) {
    if (i == teamFlag) {
      continue;
    }

    if (!isFlagSet(flags, i)) {
      continue;
    }

    team = getTeamForFlag(i);
    listLen += formatex(list[listLen], charsmax(list) - listLen,
        "%L, ", id, CMD_TEAM_KEYS[team]);
  }

  list[max(0, listLen - 2)] = EOS;
  return formatex(dst, len, "%L %s", id, "CMD_BAD_TEAM", list);
}

stock bool: isValidCommand({any,Command}: command) {
  return command <= g_numCommands && command > Invalid_Command;
}

stock commandToIndex(Command: command) {
  assert isValidCommand(command);
  return command - 1;
}

stock bool: isValidAlias({any,Alias}: alias) {
  return alias <= g_numAliases && alias > Invalid_Alias;
}

stock aliasToIndex(Alias: alias) {
  assert isValidAlias(alias);
  return alias - 1;
}

stock bool: isAliasBound(Alias: alias) {
  loadAlias(alias);
  new const Command: command = g_tempAlias[alias_Command];
  LoggerLogDebug("isAliasBound(\"%s\") == %s; g_tempAlias[alias_Command] = %d",
      g_tempAlias[alias_String],
      isValidCommand(command) ? "true" : "false",
      command);
  return isValidCommand(command);
}

stock loadCommand(Command: command) {
  if (command == g_Command) {
    return;
  }

  ArrayGetArray(g_commandsList, commandToIndex(command), g_tempCommand);
  g_Command = command;
  LoggerLogDebug("Loaded command %d into g_tempCommand", g_Command);
}

stock commitCommand(Command: command) {
  ArraySetArray(g_commandsList, commandToIndex(command), g_tempCommand);
  g_Command = command;
  LoggerLogDebug("Committed command %d into g_tempCommand", g_Command);
}

stock invalidateCommand() {
  g_Command = Invalid_Command;
  LoggerLogDebug("Invalidated g_tempCommand");
}

stock loadAlias(Alias: alias) {
  if (alias == g_Alias) {
      return;
  }

  ArrayGetArray(g_aliasesList, aliasToIndex(alias), g_tempAlias);
  g_Alias = alias;
  LoggerLogDebug("Loaded alias %d into g_tempAlias", g_Alias);
}

stock commitAlias(Alias: alias) {
  ArraySetArray(g_aliasesList, aliasToIndex(alias), g_tempAlias);
  g_Alias = alias;
  LoggerLogDebug("Committed alias %d into g_tempAlias", g_Alias);
}

stock invalidateAlias() {
  g_Alias = Invalid_Alias;
  LoggerLogDebug("Invalidated g_tempAlias");
}

stock outputArrayContents(Array: array){
  new list[32], len = 0;
  new const size = ArraySize(array);
  for (new i = 0; i < size; i++) {
    len += format(list[len], charsmax(list) - len, "%d, ", ArrayGetCell(array, i));
  }

  list[max(0, len - 2)] = EOS;
  LoggerLogDebug("Array: %d contents = { %s } (size=%d)", array, list, size);
}

bindAlias(Alias: alias, Command: command) {
  assert isValidCommand(command);
  loadAlias(alias);
  LoggerLogDebug("Binding alias %d (\"%s\") to command %d",
      alias, g_tempAlias[alias_String], command);
  if (isAliasBound(alias)) {
    unbindAlias(alias);
  }

  loadAlias(alias);
  g_tempAlias[alias_Command] = command;
  commitAlias(alias);

  loadCommand(command);
  new const Array: aliasesList = g_tempCommand[command_Aliases];
#if defined COMPILE_FOR_DEBUG
  outputArrayContents(aliasesList);
#endif
  LoggerLogDebug("Pushing alias %d (\"%s\") to Array: %d (size=%d)",
      alias, g_tempAlias[alias_String], aliasesList, ArraySize(aliasesList));

  ArrayPushCell(aliasesList, alias);
#if defined COMPILE_FOR_DEBUG
  outputArrayContents(aliasesList);
#endif
}

unbindAlias(Alias: alias) {
  if (!isAliasBound(alias)) {
    return;
  }

  new const Command: command = g_tempAlias[alias_Command];
  loadCommand(command);

  new const Array: aliasesList = g_tempCommand[command_Aliases];
  assert aliasesList != Invalid_Array;

  new bool: foundAlias = false;
  new const size = ArraySize(aliasesList);
#if defined COMPILE_FOR_DEBUG
  outputArrayContents(aliasesList);
#endif
  LoggerLogDebug("Removing alias %d (\"%s\") from Array: %d (size=%d)",
      alias, g_tempAlias[alias_String], aliasesList, size);

  for (new i = 0; i < size; i++) {
    // @TODO: Binary search could be implemented here
    if (ArrayGetCell(aliasesList, i) == alias) {
      ArrayDeleteItem(aliasesList, i);
      foundAlias = true;
      break;
    }
  }

#if defined COMPILE_FOR_DEBUG
  outputArrayContents(aliasesList);
#endif
  assert foundAlias;
  if (ArraySize(aliasesList) == 0) {
    LoggerLogWarn("Command %d no longer has any aliases bound to it (leak)!", command);
  }

  g_tempAlias[alias_Command] = Invalid_Command;
  commitAlias(alias);
  LoggerLogDebug("Unbound alias %d (\"%s\") from command %d",
      alias, g_tempAlias[alias_String], command);
}

Alias: registerAlias(const Command: command, alias[]) {
  strtolower(alias);
  if (isStringEmpty(alias)) {
    LoggerLogError("Cannot register an empty alias!");
    return Invalid_Alias;
  } else if (!isValidCommand(command)) {
    LoggerLogError("Invalid command specified for alias \"%s\": %d", alias, command);
    return Invalid_Alias;
  }

  new Alias: aliasId;
  if (g_aliasesMap != Invalid_Trie && TrieGetCell(g_aliasesMap, alias, aliasId)) {
    loadAlias(aliasId);
    LoggerLogDebug("Remapping existing alias %d (\"%s\"), from command %d to %d",
        aliasId, g_tempAlias[alias_String], g_tempAlias[alias_Command], command);
    bindAlias(aliasId, command);
    return aliasId;
  }

  if (g_aliasesList == Invalid_Array) {
    g_aliasesList = ArrayCreate(alias_t, INITIAL_ALIASES_SIZE);
    g_numAliases = 0;
    LoggerLogDebug("Created g_aliasesList = Array: %d", g_aliasesList);
  }

  if (g_aliasesMap == Invalid_Trie) {
    g_aliasesMap = TrieCreate();
    LoggerLogDebug("Created g_aliasesMap = Trie: %d", g_aliasesMap);
  }

  copy(g_tempAlias[alias_String], alias_String_length, alias);
  g_tempAlias[alias_Command] = Invalid_Command;
  aliasId = ArrayPushArray(g_aliasesList, g_tempAlias)+1;
  TrieSetCell(g_aliasesMap, g_tempAlias[alias_String], aliasId);
  g_Alias = aliasId;

  g_numAliases++;
  assert g_numAliases == ArraySize(g_aliasesList);
  assert g_numAliases == TrieGetSize(g_aliasesMap);

  bindAlias(aliasId, command);
  LoggerLogDebug("Registered alias %d (\"%s\") for command %d", aliasId, alias, command);
  return aliasId;
}

stock checkFlags(const bits, const Command: command, const alias[]) {
  if (!isFlagSet(bits, FLAG_METHOD_SAY)
   && !isFlagSet(bits, FLAG_METHOD_SAY_TEAM)) {
    LoggerLogWarn(
        "Command %d with alias \"%s\" does not have a flag specifying a say \
        method which activates it ('%c' for 'say' and/or '%c' for 'say_team')",
        command, alias, FLAG_METHOD_SAY_CH, FLAG_METHOD_SAY_TEAM_CH);
  }

  if (!isFlagSet(bits, FLAG_STATE_ALIVE)
   && !isFlagSet(bits, FLAG_STATE_DEAD)) {
    LoggerLogWarn(
        "Command %d with alias \"%s\" does not have a flag specifying a state \
        which a player must be in order to activate it ('%c' for alive and/or \
        '%c' for dead)",
        command, alias, FLAG_STATE_ALIVE_CH, FLAG_STATE_DEAD_CH);
  }

  if (areFlagsNotSet(This_Logger, bits, FLAG_TEAM_UNASSIGNED, FLAG_TEAM_T, FLAG_TEAM_CT, FLAG_TEAM_SPECTATOR)) {
    LoggerLogWarn(
        "Command %d with alias \"%s\" does not have a flag specifying a team \
        which a player must be on in order to activate it ('%c' for UNASSIGNED \
        and/or '%c' for TERRORIST and/or '%c' for CT and/or '%c' for SPECTATOR)",
        command, alias, FLAG_TEAM_UNASSIGNED_CH, FLAG_TEAM_T_CH, FLAG_TEAM_CT_CH, FLAG_TEAM_SPECTATOR_CH);
  }

  if (!isFlagSet(bits, FLAG_STATE_DEAD)
    && isFlagSet(bits, FLAG_TEAM_SPECTATOR)) {
    LoggerLogWarn(
        "Command %d with alias \"%s\" specifies a player must be a spectator \
        ('%c'), however the dead flag ('%c') is not set",
        command, alias, FLAG_TEAM_SPECTATOR_CH, FLAG_STATE_DEAD_CH);
  }
}

/*******************************************************************************
 * Console Commands
 ******************************************************************************/

public onPrintCommands(id) {
  console_print(id, "Commands:");
  console_print(id, "%3s %64s %8s %8s %16s %4s %s",
      "ID", "DESCRIPTION", "FLAGS", "ADMIN", "PLUGIN", "FUNC", "ALIASES");
  new flags[16], adminFlags[16], filename[64], aliases[256];
  for (new i = 1; i <= g_numCommands; i++) {
    loadCommand(i);
    getCustomFlags(g_tempCommand[command_Flags], flags, charsmax(flags));
    get_flags(g_tempCommand[command_AdminFlags], adminFlags, charsmax(adminFlags));
    get_plugin(g_tempCommand[command_PluginID],
        .filename = filename, .len1 = charsmax(filename));
    outputCommandAliases(i, aliases, charsmax(aliases));
    console_print(id, "%2d. %64.64s %8.8s %8.8s %16.16s %4d %s",
        i,
        g_tempCommand[command_Desc],
        flags,
        adminFlags,
        filename,
        g_tempCommand[command_FuncID],
        aliases);
  }

  console_print(id, "%d commands registered.", g_numCommands);
}

stock outputCommandAliases(const Command: command, dst[], const len){
  new copyLen = 0;
  loadCommand(command);
  new const Array: array = g_tempCommand[command_Aliases];
  new const size = ArraySize(array);
  for (new i = 0; i < size; i++) {
    loadAlias(ArrayGetCell(array, i));
    copyLen += format(dst[copyLen], len - copyLen, "%s, ", g_tempAlias[alias_String]);
  }

  copyLen = max(0, copyLen - 2);
  dst[copyLen] = EOS;
  LoggerLogDebug("Command %d aliases = { %s } (size=%d)", command, dst, size);
  return copyLen;
}

public onPrintAliases(id) {
  console_print(id, "Aliases:");
  console_print(id, "%3s %32s %s", "ID", "ALIAS", "COMMAND");

  for (new i = 1; i <= g_numAliases; i++) {
    loadAlias(i);
    console_print(id, "%2d. %32.32s %d", i, g_tempAlias[alias_String], g_tempAlias[alias_Command]);
  }

  console_print(id, "%d aliases registered.", g_numAliases);
}

/*******************************************************************************
 * Natives
 ******************************************************************************/

// native cmd_setError(const error[]);
public native_setError(plugin, numParams) {
  if (!numParamsEqual(1, numParams)) {
    return;
  }

  if (!isOnBeforeCommand) {
    ThrowIllegalStateException(This_Logger,
        "Cannot set error message for command outside of cmd_onBeforeCommand forward");
    return;
  }

  get_string(1, g_szError, charsmax(g_szError));
  LoggerLogDebug("Rejected reason set to \"%s\"", g_szError);
}

//native Command: cmd_registerCommand(
//    const alias[],
//    const handle[],
//    const flags[] = "12,ad,utcs",
//    const desc[] = "",
//    const adminFlags = ADMIN_ALL);
public Command: native_registerCommand(plugin, numParams) {
  if (!numParamsEqual(5, numParams)) {
    return Invalid_Command;
  }

  if (g_commandsList == Invalid_Array) {
    g_commandsList = ArrayCreate(command_t, INITIAL_COMMANDS_SIZE);
    g_numCommands = 0;
    LoggerLogDebug("Created g_commandsList = Array: %d", g_commandsList);
  }

  new handle[32];
  get_string(2, handle, charsmax(handle));
  if (isStringEmpty(handle)) {
    ThrowIllegalArgumentException(This_Logger, "Cannot register a command with an empty handle!");
    return Invalid_Command;
  }

  new const funcId = get_func_id(handle, plugin);
  if (funcId == -1) {
    new filename[32];
    get_plugin(plugin, filename, charsmax(filename));
    ThrowIllegalArgumentException(This_Logger, "Function \"%s\" does not exist within \"%s\"!", handle, filename);
    return Invalid_Command;
  }

  new flags[32];
  get_string(3, flags, charsmax(flags));
  new const bits = readCustomFlags(flags);
  LoggerLogDebug("Flags = %s %X", flags, bits);

  new const adminFlags = get_param(5);

  get_string(4, g_tempCommand[command_Desc], command_Desc_length);
  g_tempCommand[command_Flags] = bits;
  g_tempCommand[command_AdminFlags] = adminFlags;
  g_tempCommand[command_PluginID] = plugin;
  g_tempCommand[command_FuncID] = funcId;
  g_tempCommand[command_Aliases] = ArrayCreate(1, 2);
  g_Command = ArrayPushArray(g_commandsList, g_tempCommand) + 1;

  g_numCommands++;
  assert g_numCommands == ArraySize(g_commandsList);

  LoggerLogDebug("Created command %d[command_Aliases] = Array: %d",
      g_Command, g_tempCommand[command_Aliases]);
  LoggerLogDebug("Registered command as Command: %d", g_Command);

  new alias[alias_String_length + 1];
  get_string(1, alias, charsmax(alias));
  if (registerAlias(g_Command, alias) == Invalid_Alias) {
    LoggerLogWarn("Command %d registered without an alias!", g_Command);
  }

  checkFlags(bits, g_Command, alias);

  if (g_fw[onCommandRegistered] == INVALID_HANDLE) {
    LoggerLogDebug("Creating forward cmd_onCommandRegistered");
    g_fw[onCommandRegistered] = CreateMultiForward(
        "cmd_onCommandRegistered", ET_IGNORE,
        FP_CELL, FP_STRING, FP_CELL, FP_STRING, FP_CELL);
    LoggerLogDebug("g_fw[onCommandRegistered] = %d", g_fw[onCommandRegistered]);
  }

  LoggerLogDebug("Calling cmd_onCommandRegistered");
  ExecuteForward(g_fw[onCommandRegistered], g_fw[fwReturn],
      g_Command, alias, bits, g_tempCommand[command_Desc], adminFlags);
  return g_Command;
}

//native Alias: cmd_registerAlias(const Command: command, const alias[]);
public Alias: native_registerAlias(plugin, numParams) {
  if (!numParamsEqual(2, numParams)) {
    return Invalid_Alias;
  }

  new alias[alias_String_length + 1];
  get_string(2, alias, charsmax(alias));
  return registerAlias(toCommand(get_param(1)), alias);
}

// native Command: cmd_findCommand(const alias[]);
public Command: native_findCommand(plugin, numParams) {
  if (!numParamsEqual(1, numParams)) {
    return Invalid_Command;
  }

  if (g_commandsList == Invalid_Array || g_numCommands == 0) {
    return Invalid_Command;
  }

  new alias[alias_String_length + 1];
  get_string(1, alias, charsmax(alias));

  new Alias: aliasId;
  if (g_aliasesMap == Invalid_Trie || !TrieGetCell(g_aliasesMap, alias, aliasId)) {
    return Invalid_Command;
  }

  assert isValidAlias(aliasId);
  loadAlias(aliasId);
  new const Command: command = g_tempAlias[alias_Command];
  LoggerLogDebug("cmd_findCommand(\"%s\") == %d", alias, command);
  return command;
}

// native bool: cmd_isValidCommand(const {any,Command}: command);
public bool: native_isValidCommand(pluginId, numParams) {
  if (!numParamsEqual(1, numParams)) {
    return false;
  }

  return isValidCommand(get_param(1));
}

// native bool: cmd_isValidAlias(const {any,Alias}: alias);
public bool: native_isValidAlias(plugin, numParams) {
  if (!numParamsEqual(1, numParams)) {
    return false;
  }

  return isValidAlias(get_param(1));
}

// native cmd_getNumCommands();
public native_getNumCommands(plugin, numParams) {
  if (!hasNoParams(numParams)) {
    return 0;
  }

  return g_numCommands;
}

// native cmd_getNumAliases();
public native_getNumAliases(plugin, numParams) {
  if (!hasNoParams(numParams)) {
    return 0;
  }

  return g_numAliases;
}
