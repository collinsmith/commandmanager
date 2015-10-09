#define VERSION_STRING "1.0.0"
#define COMPILE_FOR_DEBUG
#define MAX_NUM_PREFIXES 8
#define INITIAL_COMMANDS_SIZE 8
#define INITIAL_ALIASES_SIZE 16
#define PRINT_BUFFER_LENGTH 191

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <logger>

#include "include\\commandmanager-inc\\alias_t.inc"
#include "include\\commandmanager-inc\\command_t.inc"
#include "include\\commandmanager-inc\\command_manager_const.inc"

#include "include\\stocks\\dynamic_param_stocks.inc"
#include "include\\stocks\\flag_stocks.inc"
#include "include\\stocks\\misc_stocks.inc"
#include "include\\stocks\\param_test_stocks.inc"
#include "include\\stocks\\string_stocks.inc"

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

static Logger: g_Logger = Invalid_Logger;

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
}; static g_fw[Forwards] = { 0, INVALID_HANDLE, INVALID_HANDLE,
        INVALID_HANDLE, INVALID_HANDLE, INVALID_HANDLE };

static Array: g_commandsList, g_numCommands;
static g_tempCommand[command_t], Command: g_Command = Invalid_Command;

static Array: g_aliasesList, g_numAliases;
static g_tempAlias[alias_t], Alias: g_Alias = Invalid_Alias;

static Trie: g_aliasesMap;
static Trie: g_prefixesMap;

static g_szCommandBuffer[192];

static g_szError[192];
static bool: isOnBeforeCommand;

static g_pCvar_Prefixes;

public plugin_precache() {
    g_Logger = LoggerCreate();
#if defined COMPILE_FOR_DEBUG
    LoggerSetVerbosity(g_Logger, Severity_Lowest);
    LoggerSetVerbosity(All_Loggers, Severity_Lowest);
#endif
}

public plugin_natives() {
    register_library("command_manager");

    register_native("cmd_setError", "_setError", 0);

    register_native("cmd_registerCommand", "_registerCommand", 0);
    register_native("cmd_registerAlias", "_registerAlias", 0);

    register_native("cmd_getCommandFromAlias", "_getCommandFromAlias", 0);

    register_native("cmd_isValidCommand", "_isValidCommand", 0);
    register_native("cmd_isValidAlias", "_isValidAlias", 0);

    register_native("cmd_getNumCommands", "_getNumCommands", 0);
    register_native("cmd_getNumAliases", "_getNumAliases", 0);
}

public plugin_init() {
    new buildId[32];
    getBuildId(buildId);
    register_plugin("Command Manager", buildId, "Tirant");

    create_cvar(
            "command_manager_version",
            buildId,
            FCVAR_SPONLY,
            "Current version of Command Manager being used");

    registerConCmds();
    createForwards();

    g_pCvar_Prefixes = create_cvar(
            "command_prefixes",
            "/.!",
            FCVAR_SERVER|FCVAR_SPONLY,
            "List of all symbols that can preceed commands");
    hook_cvar_change(g_pCvar_Prefixes, "cvar_onPrefixesAltered");

    new prefixes[MAX_NUM_PREFIXES];
    get_pcvar_string(g_pCvar_Prefixes, prefixes, charsmax(prefixes));
    cvar_onPrefixesAltered(g_pCvar_Prefixes, NULL_STRING, prefixes);

    register_clcmd("say", "clcmd_onSay");
    register_clcmd("say_team", "clcmd_onSayTeam");
}

stock getBuildId(buildId[], len = sizeof buildId) {
#if defined COMPILE_FOR_DEBUG
    return formatex(buildId, len - 1,
            "%s [%s] [DEBUG]", VERSION_STRING, __DATE__);
#else
    return formatex(buildId, len - 1,
            "%s [%s]", VERSION_STRING, __DATE__);
#endif
}

registerConCmds() {
    registerConCmd(
            .prefix = "cmd",
            .command = "list",
            .function = "printCommands",
            .description = "Prints the list of commands with their details",
            .logger = g_Logger);

    registerConCmd(
            .prefix = "cmd",
            .command = "cmds",
            .function = "printCommands",
            .description = "Prints the list of commands with their details",
            .logger = g_Logger);

    registerConCmd(
            .prefix = "cmd",
            .command = "commands",
            .function = "printCommands",
            .description = "Prints the list of commands with their details",
            .logger = g_Logger);

    registerConCmd(
            .prefix = "cmd",
            .command = "aliases",
            .function = "printAliases",
            .description = "Prints the list of commands with their details",
            .logger = g_Logger);
}

createForwards() {
    createOnBeforeCommand();
    createOnCommand();
}

createOnBeforeCommand() {
    LoggerLogDebug(g_Logger, "Creating forward cmd_onBeforeCommand");
    g_fw[onBeforeCommand] = CreateMultiForward("cmd_onBeforeCommand",
            ET_STOP,
            FP_CELL, 
            FP_CELL, 
            FP_CELL);
    LoggerLogDebug(g_Logger,
            "g_fw[onBeforeCommand] = %d",
            g_fw[onBeforeCommand]);
}

createOnCommand() {
    LoggerLogDebug(g_Logger, "Creating forward cmd_onCommand");
    g_fw[onCommand] = CreateMultiForward("cmd_onCommand",
            ET_IGNORE,
            FP_CELL, 
            FP_CELL, 
            FP_CELL);
    LoggerLogDebug(g_Logger,
            "g_fw[onCommand] = %d",
            g_fw[onCommand]);
}

public cvar_onPrefixesAltered(pCvar, const oldValue[], const newValue[]) {
    assert pCvar == g_pCvar_Prefixes;
    if (g_prefixesMap == Invalid_Trie) {
        g_prefixesMap = TrieCreate();
        LoggerLogDebug(g_Logger,
                "Initialized g_prefixesMap as Trie: %d",
                g_prefixesMap);
    } else {
        TrieClear(g_prefixesMap);
        LoggerLogDebug(g_Logger, "Cleared g_prefixesMap");
    }
    
    LoggerLogDebug(g_Logger,
            "Updating command prefixes table to: \"%s\"",
            newValue);
    
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
        LoggerLogDebug(g_Logger, "Creating forward cmd_onPrefixesChanged");
        g_fw[onPrefixesChanged] = CreateMultiForward(
                "cmd_onPrefixesChanged",
                ET_IGNORE,
                FP_STRING,
                FP_STRING);
        LoggerLogDebug(g_Logger,
                "g_fw[onPrefixesChanged] = %d",
                g_fw[onPrefixesChanged]);
    }
    
    ExecuteForward(g_fw[onPrefixesChanged], g_fw[fwReturn], oldValue, newValue);
}



public clcmd_onSay(id) {
    read_args(g_szCommandBuffer, charsmax(g_szCommandBuffer));
    return checkCommandAndHandle(
            id, false, g_szCommandBuffer, charsmax(g_szCommandBuffer));
}

public clcmd_onSayTeam(id) {
    read_args(g_szCommandBuffer, charsmax(g_szCommandBuffer));
    return checkCommandAndHandle(
            id, true, g_szCommandBuffer, charsmax(g_szCommandBuffer));
}

/**
 * Checks if a command is used with a correct prefix and triggers it.
 *
 * @param id          Player index who entered the command
 * @param teamCommand {@literal true} if it was sent via team only chat,
 *                        otherwise {@literal false}
 * @param args        Message args being sent
 * @return {@literal PLUGIN_CONTINUE} in the event that this was not a command
 *         or did not use a valid prefix, otherwise {@literal PLUGIN_CONTINUE}
 *         or {@literal PLUGIN_HANDLED} depending on whether or not the command
 *         should be hidden or not from the chat area
 */
checkCommandAndHandle(
        const id,
        const bool: teamCommand,
        args[],
        const len) {
    strtolower(args);
    remove_quotes(args);
    
    new temp[2], prefix;
    temp[0] = args[0];
    if (!TrieGetCell(g_prefixesMap, temp, prefix)) {
        return PLUGIN_CONTINUE;
    }
    
    // This was from the legacy code. I don't think this is neccessary.
    new alias[alias_String_length+1];
    argbreak(
            args[1],
            alias,
            charsmax(alias),
            args,
            len);
    
    new Alias: aliasId;
    if (TrieGetCell(g_aliasesMap, alias, aliasId)) {
        loadAlias(aliasId);
        LoggerLogDebug(g_Logger,
                "Alias found: %d (\"%s\") is bound to command %d",
                aliasId,
                g_tempAlias[alias_String],
                g_tempAlias[alias_Command]);
        return tryExecutingCommand(
                prefix,
                g_tempAlias[alias_Command],
                id,
                teamCommand,
                args,
                len);
    }
    
    return PLUGIN_CONTINUE;
}

/**
 * Attemps to execute the given command for a specified player if their current
 * state meets the criteria that the command definition requires, and the
 * command is not blocked by another extension.
 *
 * @param prefix      Prefix used when executing command
 * @param command     Command identifier to try and execute
 * @param id          Player index who is executing the command
 * @param teamCommand {@literal true} if it was sent via team only chat,
 *                        otherwise {@literal false}
 * @param args        Additional arguments passed with the command (e.g.,
 *                    /kill <player>, where the value of <player> would be
 *                    this parameter)
 * @param len         Max number of bytes in {@param args}, i.e., {@code sizeof
 *                        {@param args} - 1}
 */
tryExecutingCommand(
        const prefix,
        const Command: command,
        const id,
        const bool: isTeamCommand,
        args[],
        const len) {
    assert isValidCommand(command);
    assert isValidId(id);
    
    loadCommand(command);
    
    new const bool: hasAccess
            = bool:(access(id, g_tempCommand[command_AdminFlags]));
    if (!hasAccess) {
        cmd_printColor(id, "%L", id, "CMD_NO_ACCESS");
        return PLUGIN_HANDLED;
    }

    new const flags = g_tempCommand[command_Flags];
    if (!areFlagsSet(g_Logger, flags, FLAG_METHOD_SAY, FLAG_METHOD_SAY_TEAM)) {
        return PLUGIN_CONTINUE;
    } else {
        switch (getXorFlag(g_Logger, flags, FLAG_METHOD_SAY, FLAG_METHOD_SAY_TEAM)) {
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

    if (!areFlagsSet(g_Logger, flags, FLAG_STATE_ALIVE, FLAG_STATE_DEAD)) {
        return PLUGIN_CONTINUE;
    } else {
        new const bool: isAlive = bool:(is_user_alive(id));
        switch (getXorFlag(g_Logger, flags, FLAG_STATE_ALIVE, FLAG_STATE_DEAD)) {
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
    if (!isFlagSet(g_Logger, flags, teamFlag)) {
        buildValidTeamsMessage(
                id,
                g_szError, charsmax(g_szError),
                teamFlag,
                flags);
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
            LoggerLogWarn(g_Logger,
                    "A command was blocked without a reason given.");
        } else {
            cmd_printColor(id, g_szError);
        }
        
        return PLUGIN_HANDLED;
    }
    
    new name[32];
    argparse(args, 0, name, charsmax(name));
    /*argbreak(
            args[1],
            name,
            charsmax(name),
            args,
            len);*/

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
        case 2: length += copy(
                buffer[offset], PRINT_BUFFER_LENGTH-offset, message);
        default: length += vformat(
                buffer[offset], PRINT_BUFFER_LENGTH-offset, message, 3);
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
        
        if (!isFlagSet(g_Logger, flags, i)) {
            continue;
        }

        team = getTeamForFlag(i);
        listLen += formatex(list[listLen], charsmax(list)-listLen,
                "%L, ", id, CMD_TEAM_KEYS[team]);
    }
    
    list[max(0, listLen-2)] = EOS;
    return formatex(dst, len, "%L %s", id, "CMD_BAD_TEAM", list);
}

stock bool: isValidCommand({any,Command}: command) {
    return command <= g_numCommands && command > Invalid_Command;
}

stock commandToIndex(Command: command) {
    assert isValidCommand(command);
    return command-1;
}

stock bool: isValidAlias({any,Alias}: alias) {
    return alias <= g_numAliases && alias > Invalid_Alias;
}

stock aliasToIndex(Alias: alias) {
    assert isValidAlias(alias);
    return alias-1;
}

stock bool: isAliasBound(Alias: alias) {
    loadAlias(alias);
    new const Command: command = g_tempAlias[alias_Command];
    LoggerLogDebug(g_Logger,
            "isAliasBound(\"%s\") == %s; g_tempAlias[alias_Command] = %d",
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
    LoggerLogDebug(g_Logger, "Loaded command %d into g_tempCommand", g_Command);
}

stock commitCommand(Command: command) {
    ArraySetArray(g_commandsList, commandToIndex(command), g_tempCommand);
    g_Command = command;
    LoggerLogDebug(g_Logger,
            "Committed command %d into g_tempCommand", g_Command);
}

stock invalidateCommand() {
    g_Command = Invalid_Command;
    LoggerLogDebug(g_Logger, "Invalidated g_tempCommand");
}

stock loadAlias(Alias: alias) {
    if (alias == g_Alias) {
        return;
    }

    ArrayGetArray(g_aliasesList, aliasToIndex(alias), g_tempAlias);
    g_Alias = alias;
    LoggerLogDebug(g_Logger, "Loaded alias %d into g_tempAlias", g_Alias);
}

stock commitAlias(Alias: alias) {
    ArraySetArray(g_aliasesList, aliasToIndex(alias), g_tempAlias);
    g_Alias = alias;
    LoggerLogDebug(g_Logger, "Committed alias %d into g_tempAlias", g_Alias);
}

stock invalidateAlias() {
    g_Alias = Invalid_Alias;
    LoggerLogDebug(g_Logger, "Invalidated g_tempAlias");
}

stock outputArrayContents(Array: array){
    new list[32], len = 0;
    new const size = ArraySize(array);
    for (new i = 0; i < size; i++) {
        len += format(list[len], charsmax(list)-len,
                "%d, ", ArrayGetCell(array, i));
    }

    list[max(0, len-2)] = EOS;
    LoggerLogDebug(g_Logger,
            "Array: %d contents = { %s } (size=%d)",
            array,
            list,
            size);
}

bindAlias(Alias: alias, Command: command) {
    assert isValidCommand(command);
    loadAlias(alias);
    LoggerLogDebug(g_Logger,
            "Binding alias %d (\"%s\") to command %d",
            alias,
            g_tempAlias[alias_String],
            command);

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
    LoggerLogDebug(g_Logger,
            "Pushing alias %d (\"%s\") to Array: %d (size=%d)",
            alias,
            g_tempAlias[alias_String],
            aliasesList,
            ArraySize(aliasesList));
            
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
    LoggerLogDebug(g_Logger,
            "Removing alias %d (\"%s\") from Array: %d (size=%d)",
            alias,
            g_tempAlias[alias_String],
            aliasesList,
            size);

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
        LoggerLogWarn(g_Logger,
                "Command %d no longer has any aliases bound to it (leak)!",
                command);
    }
    
    g_tempAlias[alias_Command] = Invalid_Command;
    commitAlias(alias);
    LoggerLogDebug(g_Logger,
            "Unbound alias %d (\"%s\") from command %d",
            alias,
            g_tempAlias[alias_String],
            command);
}

Alias: registerAlias(const Command: command, alias[]) {
    strtolower(alias);
    if (isStringEmpty(alias)) {
        LoggerLogError(g_Logger,
                "Cannot register an empty alias!");
        return Invalid_Alias;
    } else if (!isValidCommand(command)) {
        LoggerLogError(g_Logger,
                "Invalid command specified for alias \"%s\": %d",
                alias,
                command);
        return Invalid_Alias;
    }

    new Alias: aliasId;
    if (g_aliasesMap != Invalid_Trie
            && TrieGetCell(g_aliasesMap, alias, aliasId)) {
        loadAlias(aliasId);
        LoggerLogDebug(g_Logger,
                "Remapping existing alias %d (\"%s\"), from command %d to %d",
                aliasId,
                g_tempAlias[alias_String],
                g_tempAlias[alias_Command],
                command);
        bindAlias(aliasId, command);
        return aliasId;
    }

    if (g_aliasesList == Invalid_Array) {
        g_aliasesList = ArrayCreate(alias_t, INITIAL_ALIASES_SIZE);
        g_numAliases = 0;
        LoggerLogDebug(g_Logger,
                "Initialized g_aliasesList as Array: %d",
                g_aliasesList);
    }

    if (g_aliasesMap == Invalid_Trie) {
        g_aliasesMap = TrieCreate();
        LoggerLogDebug(g_Logger,
                "Initialized g_aliasesMap as Trie: %d",
                g_aliasesMap);
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
    LoggerLogDebug(g_Logger,
            "Registered alias %d (\"%s\") for command %d",
            aliasId,
            alias,
            command);
    return aliasId;
}

stock checkFlags(const bits, const Command: command, const alias[]) {
    if (!isFlagSet(g_Logger, bits, FLAG_METHOD_SAY)
            && !isFlagSet(g_Logger, bits, FLAG_METHOD_SAY_TEAM)) {
        LoggerLogWarn(g_Logger,
                "Command %d with alias \"%s\" does not have a flag specifying \
                a say method which activates it ('%c' for 'say' and/or \
                '%c' for 'say_team')",
                command,
                alias,
                FLAG_METHOD_SAY_CH,
                FLAG_METHOD_SAY_TEAM_CH);
    }

    if (!isFlagSet(g_Logger, bits, FLAG_STATE_ALIVE)
            && !isFlagSet(g_Logger, bits, FLAG_STATE_DEAD)) {
        LoggerLogWarn(g_Logger,
                "Command %d with alias \"%s\" does not have a flag specifying \
                a state which a player must be in order to activate it ('%c' \
                for alive and/or '%c' for dead)",
                command,
                alias,
                FLAG_STATE_ALIVE_CH,
                FLAG_STATE_DEAD_CH);
    }

    if (areFlagsNotSet(g_Logger, bits, FLAG_TEAM_UNASSIGNED, FLAG_TEAM_T, FLAG_TEAM_CT, FLAG_TEAM_SPECTATOR)) {
        LoggerLogWarn(g_Logger,
                "Command %d with alias \"%s\" does not have a flag specifying \
                a team which a player must be on in order to activate it \
                ('%c' for UNASSIGNED and/or '%c' for TERRORIST and/or '%c' \
                for CT and/or '%c' for SPECTATOR)",
                command,
                alias,
                FLAG_TEAM_UNASSIGNED_CH,
                FLAG_TEAM_T_CH,
                FLAG_TEAM_CT_CH,
                FLAG_TEAM_SPECTATOR_CH);
    }

    if (!isFlagSet(g_Logger, bits, FLAG_STATE_DEAD)
            && isFlagSet(g_Logger, bits, FLAG_TEAM_SPECTATOR)) {
        LoggerLogWarn(g_Logger,
                "Command %d with alias \"%s\" specifies a player must be a \
                spectator ('%c'), however the dead flag ('%c') is not set",
                command,
                alias,
                FLAG_TEAM_SPECTATOR_CH,
                FLAG_STATE_DEAD_CH);
    }
}

/*******************************************************************************
 * Console Commands
 ******************************************************************************/

public printCommands(id) {
    //...
}

public printAliases(id) {
    //...
}

/*******************************************************************************
 * Natives
 ******************************************************************************/

// native cmd_setError(const error[]);
public _setError(pluginId, numParams) {
    if (!numParamsEqual(g_Logger, 1, numParams)) {
        return;
    }

    if (!isOnBeforeCommand) {
        LoggerLogError(g_Logger, "Cannot set error message for command outside \
                of cmd_onBeforeCommand forward");
        return;
    }

    get_string(1, g_szError, charsmax(g_szError));
    LoggerLogDebug(g_Logger,
            "Handler error string set to \"%s\"",
            g_szError);
}

// native Command: cmd_registerCommand(
//         const alias[],
//         const handle[],
//         const flags[] = "12,ad,utcs",
//         const description[] = NULL_STRING,
//         const adminFlags = ADMIN_ALL);
public Command: _registerCommand(pluginId, numParams) {
    if (!numParamsEqual(g_Logger, 5, numParams)) {
        return Invalid_Command;
    }

    if (g_commandsList == Invalid_Array) {
        g_commandsList = ArrayCreate(command_t, INITIAL_COMMANDS_SIZE);
        g_numCommands = 0;
        LoggerLogDebug(g_Logger,
                "Initialized g_commandsList as Array: %d",
                g_commandsList);
    }

    new handle[32];
    get_string(2, handle, charsmax(handle));
    if (isStringEmpty(handle)) {
        LoggerLogError(g_Logger,
                "Cannot register a command with an empty handle!");
        return Invalid_Command;
    }

    new const funcId = get_func_id(handle, pluginId);
    if (funcId == -1) {
        new filename[32];
        get_plugin(pluginId, filename, charsmax(filename));
        LoggerLogError(g_Logger,
                "Function \"%s\" does not exist within \"%s\"!",
                handle,
                filename);
        return Invalid_Command;
    }

    new flags[32];
    get_string(3, flags, charsmax(flags));
    new const bits = readCustomFlags(flags, g_Logger);
    LoggerLogDebug(g_Logger, "Flags = %s %X", flags, bits);
    
    new const adminFlags = get_param(5);
    
    get_string(4, g_tempCommand[command_Desc], command_Desc_length);
    g_tempCommand[command_Flags] = bits;
    g_tempCommand[command_AdminFlags] = adminFlags;
    g_tempCommand[command_PluginID] = pluginId;
    g_tempCommand[command_FuncID] = funcId;
    g_tempCommand[command_Aliases] = ArrayCreate(1, 2);
    g_Command = ArrayPushArray(g_commandsList, g_tempCommand)+1;

    g_numCommands++;
    assert g_numCommands == ArraySize(g_commandsList);

    LoggerLogDebug(g_Logger,
            "Initialized command %d[command_Aliases] as Array: %d",
            g_Command,
            g_tempCommand[command_Aliases]);

    LoggerLogDebug(g_Logger,
            "Registered command as Command: %d", g_Command);

    new alias[alias_String_length+1];
    get_string(1, alias, charsmax(alias));
    if (registerAlias(g_Command, alias) == Invalid_Alias) {
        LoggerLogWarn(g_Logger,
                "Command %d registered without an alias!", g_Command);
    }

    checkFlags(bits, g_Command, alias);
    
    if (g_fw[onCommandRegistered] == INVALID_HANDLE) {
        LoggerLogDebug(g_Logger, "Creating forward cmd_onCommandRegistered");
        g_fw[onCommandRegistered] = CreateMultiForward(
                "cmd_onCommandRegistered",
                ET_IGNORE,
                FP_CELL,
                FP_STRING,
                FP_CELL,
                FP_STRING,
                FP_CELL);
        LoggerLogDebug(g_Logger,
                "g_fw[onCommandRegistered] = %d",
                g_fw[onCommandRegistered]);
    }

    LoggerLogDebug(g_Logger, "Calling cmd_onCommandRegistered");
    ExecuteForward(g_fw[onCommandRegistered], g_fw[fwReturn],
            g_Command,
            alias,
            bits,
            g_tempCommand[command_Desc],
            adminFlags);
            
    return g_Command;
}

// native Alias: cmd_registerAlias(
//         const Command: command,
//         const alias[]);
public Alias: _registerAlias(pluginId, numParams) {
    if (!numParamsEqual(g_Logger, 2, numParams)) {
        return Invalid_Alias;
    }

    new alias[alias_String_length+1];
    get_string(2, alias, charsmax(alias));
    return registerAlias(toCommand(get_param(1)), alias);
}

// native Command: cmd_getCommandFromAlias(const alias[]);
public Command: _getCommandFromAlias(pluginId, numParams) {
    if (!numParamsEqual(g_Logger, 1, numParams)) {
        return Invalid_Command;
    }

    if (g_commandsList == Invalid_Array || g_numCommands == 0) {
        return Invalid_Command;
    }

    new alias[alias_String_length+1];
    get_string(1, alias, charsmax(alias));
    
    new Alias: aliasId;
    if (g_aliasesMap == Invalid_Trie
            || !TrieGetCell(g_aliasesMap, alias, aliasId)) {
        return Invalid_Command;
    }

    assert isValidAlias(aliasId);
    loadAlias(aliasId);
    new const Command: command = g_tempAlias[alias_Command];
    LoggerLogError(g_Logger,
            "cmd_getCommandFromAlias(\"%s\") == %d",
            alias,
            command);
    return command;
}

// native bool: cmd_isValidCommand(const {any,Command}: command);
public bool: _isValidCommand(pluginId, numParams) {
    if (!numParamsEqual(g_Logger, 1, numParams)) {
        return false;
    }

    return isValidCommand(get_param(1));
}

// native bool: cmd_isValidAlias(const {any,Alias}: alias);
public bool: _isValidAlias(pluginId, numParams) {
    if (!numParamsEqual(g_Logger, 1, numParams)) {
        return false;
    }

    return isValidAlias(get_param(1));
}

// native cmd_getNumCommands();
public _getNumCommands(pluginId, numParams) {
    if (!hasNoParams(g_Logger, numParams)) {
        return -1;
    }

    return g_numCommands;
}

// native cmd_getNumAliases();
public _getNumAliases(pluginId, numParams) {
    if (!hasNoParams(g_Logger, numParams)) {
        return -1;
    }

    return g_numAliases;
}