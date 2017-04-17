#define VERSION_STRING "1.0.0"

#include <amxmodx>
#include <logger>

#include "include/commands/commands.inc"

static const TEST[][] = {
    "FAILED",
    "PASSED"
};

static tests, passed;
static bool: isEqual;

public plugin_init() {
    register_plugin("Command Manager Tests", VERSION_STRING, "Tirant");
    
    log_amx("Testing command_manager");
    tests = passed = 0;

    test_registerCommand();

    log_amx("Finished Stocks tests: %s (%d/%d)", TEST[tests == passed], passed, tests);
}

public handle1(id) {
    client_print_color(id, print_team_default, "handle1");
}

public handle2(id) {
    client_print_color(id, print_team_default, "handle2");
}

test(bool: b) {
    isEqual = b;
    tests++;
    if (isEqual) passed++;
}

test_registerCommand() {
    new numCommands;
    new Command: command;
    new alias[32];
    new handle[32];
    log_amx("Testing cmd_registerCommand");

    alias = "alias1";
    handle = "handle1";
    numCommands = cmd_getNumCommands();
    command = cmd_registerCommand(alias, handle);
    log_amx("\tcmd_registerCommand(\"%s\", \"%s\") = %d", alias, handle, command);
    test(numCommands+1 == cmd_getNumCommands());
    log_amx("\t\t%s - numCommands incremented; actual => %d -> %d", TEST[isEqual], numCommands, cmd_getNumCommands());
    test(command > Invalid_Command);
    log_amx("\t\t%s - command > Invalid_Command; actual => %d > %d", TEST[isEqual], command, Invalid_Command);
    test(command == cmd_findCommand(alias));
    log_amx("\t\t%s - command == cmd_findCommand(alias); actual => %d == %d", TEST[isEqual], command, cmd_findCommand(alias));
    
    alias = "alias2";
    handle = "handle2";
    numCommands = cmd_getNumCommands();
    command = cmd_registerCommand(alias, handle);
    log_amx("\tcmd_registerCommand(\"%s\", \"%s\") = %d", alias, handle, command);
    test(numCommands+1 == cmd_getNumCommands());
    log_amx("\t\t%s - numCommands incremented; actual => %d -> %d", TEST[isEqual], numCommands, cmd_getNumCommands());
    test(command > Invalid_Command);
    log_amx("\t\t%s - command > Invalid_Command; actual => %d > %d", TEST[isEqual], command, Invalid_Command);
    test(command == cmd_findCommand(alias));
    log_amx("\t\t%s - command == cmd_findCommand(alias); actual => %d == %d", TEST[isEqual], command, cmd_findCommand(alias));
    
    test_registerAlias();
}

test_registerAlias() {
    new numAliases;
    new Alias: alias;
    new Command: command;
    new Command: command2;
    new alias1[32];
    new alias2[32];
    new alias3[32];
    log_amx("Testing cmd_registerAlias");

    alias1 = "alias1";
    alias2 = "alias2";
    test(cmd_findCommand(alias1) != (command2 = cmd_findCommand(alias2)));
    log_amx("\t%s - cmd_findCommand(\"%s\") != cmd_findCommand(\"%s\"); \
            actual => %d != %d", TEST[isEqual],
            alias1, alias2,
            cmd_findCommand(alias1), cmd_findCommand(alias2));
    command = cmd_findCommand(alias1);
    alias = cmd_registerAlias(command, alias2);
    log_amx("\t%s - cmd_registerAlias(%d, \"%s\") = %d;", TEST[isEqual],
            command, alias2, alias);
    test(cmd_findCommand(alias1) == cmd_findCommand(alias2));
    log_amx("\t%s - cmd_findCommand(\"%s\") == cmd_findCommand(\"%s\"); \
            actual => %d == %d", TEST[isEqual],
            alias1, alias2,
            cmd_findCommand(alias1), cmd_findCommand(alias2));
    new Alias: t1 = cmd_registerAlias(command, alias1);
    new Alias: t2 = cmd_registerAlias(command, alias1);
    test(t1 == t2);
    log_amx("\t%s - cmd_registerAlias(%d, \"%s\") == cmd_registerAlias(%d, \"%s\"); \
            actual => %d == %d", TEST[isEqual],
            command, alias1,
            command, alias1,
            t1, t2);

    alias3 = "alias3";
    numAliases = cmd_getNumAliases();
    alias = cmd_registerAlias(command2, alias3);
    log_amx("\tcmd_registerAlias(%d, \"%s\") = %d;",
            command2, alias3, alias);
    test(numAliases+1 == cmd_getNumAliases());
    log_amx("\t\t%s - numAliases incremented; actual => %d -> %d", TEST[isEqual], numAliases, cmd_getNumAliases());
    test(alias > Invalid_Alias);
    log_amx("\t\t%s - alias > Invalid_Alias; actual => %d > %d", TEST[isEqual], alias, Invalid_Alias);
    test(cmd_findCommand(alias3) == command2);
    log_amx("\t\t%s - cmd_findCommand(\"%s\") == %d; \
            actual => %d == %d", TEST[isEqual],
            alias3, command2,
            cmd_findCommand(alias3), command2);
}