/* See LICENSE file for copyright and license details. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../slstatus.h"
#include "../util.h"

static char result[513]; // Буфер для вывода команды

const char *
run_command(const char *cmd)
{
    FILE *fp;
    if ((fp = popen(cmd, "r")) == NULL) {
        return NULL;
    }

    if (fgets(result, sizeof(result), fp) != NULL) {
        size_t len = strlen(result);
        if (len > 0 && result[len - 1] == '\n') {
            result[len - 1] = '\0';
        }
    } else {
        result[0] = '\0';
    }

    pclose(fp);
    return result;
}
