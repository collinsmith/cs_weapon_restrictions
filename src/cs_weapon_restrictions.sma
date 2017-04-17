#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <fakemeta_util>
#include <hamsandwich>
#include <logger>

#include "include/stocks/exception_stocks.inc"
#include "include/stocks/param_stocks.inc"
#include "include/stocks/string_stocks.inc"

//#define DEBUG_RESTRICTIONS
//#define DEBUG_FORWARDS
//#define DEBUG_STRIPPING

#define VERSION_STRING "1.0.0"

#define DEFAULT_ALLOWED_WEAPONS 0x7FFFFFFA
#define DEFAULT_FALLBACK_WEAPON CSW_KNIFE

// Weapon CBase Offsets
#define WIN32_WEAPON_OWNER_OFFSET 41
#define LINUX_WEAPON_OWNER_DIFF 4
#define WIN32_PLAYER_ACTIVE_ITEM_OFFSET 373
#define WIN32_PLAYER_NEXT_ATTACK_OFFSET 83

// Weapon entity names
new const WEAPONENTNAMES[][] = {
  "", "weapon_p228", "", "weapon_scout", "weapon_hegrenade", "weapon_xm1014",
  "weapon_c4", "weapon_mac10", "weapon_aug", "weapon_smokegrenade",
  "weapon_elite", "weapon_fiveseven", "weapon_ump45", "weapon_sg550",
  "weapon_galil", "weapon_famas", "weapon_usp", "weapon_glock18", "weapon_awp",
  "weapon_mp5navy", "weapon_m249", "weapon_m3", "weapon_m4a1", "weapon_tmp",
  "weapon_g3sg1", "weapon_flashbang", "weapon_deagle", "weapon_sg552",
  "weapon_ak47", "weapon_knife", "weapon_p90"
};

static Logger: logger = Invalid_Logger;

static allowedWeapons[MAX_PLAYERS + 1];
static fallbackWeapon[MAX_PLAYERS + 1];

static junk[32], num;

public plugin_natives() {
  register_library("cs_weapon_restrictions");

  register_native("cs_getAllowedWeapons", "native_getAllowedWeapons");
  register_native("cs_setWeaponRestrictions", "native_setWeaponRestrictions");
  register_native("cs_resetWeaponRestrictions", "native_resetWeaponRestrictions");
}

public plugin_init() {
  new buildId[32];
  getBuildId(buildId, charsmax(buildId));
  register_plugin("Weapon Restrictions API for CSTRIKE", buildId, "Tirant");

  logger = LoggerCreate();
#if defined DEBUG_RESTRICTIONS || defined DEBUG_FORWARDS || defined DEBUG_STRIPPING
  LoggerSetVerbosity(logger, Severity_Lowest);
#endif

  if (!cstrike_running()) {
    LoggerLogError(logger, "Setting fail state: CSTRIKE is required for this plugin to run!");
    set_fail_state("CSTRIKE is required for this plugin to run!");
    return;
  }

  for (new i = 1; i < sizeof WEAPONENTNAMES; i++) {
    if (!isStringEmpty(WEAPONENTNAMES[i])) {
      RegisterHam(Ham_Item_Deploy, WEAPONENTNAMES[i], "onItemDeployPost", 1);
    }
  }
}

stock getBuildId(buildId[], len) {
  return formatex(buildId, len, "%s [%s]", VERSION_STRING, __DATE__);
}

public client_putinserver(id) {
  resetWeaponRestrictions(id, false);
}

public onItemDeployPost(const eWeapon) {
  new const id = fm_getWeaponEntOwner(eWeapon);
  if (!is_user_alive(id)) {
    return;
  }

  new const weapon = cs_get_weapon_id(eWeapon);
  new const flag = (1 << weapon);
  if ((allowedWeapons[id] & flag) == flag) {
    return;
  }

  new const arsenal = get_user_weapons(id, junk, num);
  new const fallback = fallbackWeapon[id];
  new const fallbackFlag = (1 << fallback);
  if ((arsenal & fallbackFlag) == fallbackFlag) {
    if (weapon != fallback) {
#if defined DEBUG_RESTRICTIONS
      LoggerLogDebug(logger, "%s for %N is restricted, changing to fallback (%s)",
          WEAPONENTNAMES[weapon], id, WEAPONENTNAMES[fallback]);
#endif
      engclient_cmd(id, WEAPONENTNAMES[fallback]);
    }
  } else {
#if defined DEBUG_RESTRICTIONS
    LoggerLogDebug(logger, "%s for %N is restricted and player does not own fallback (%s)",
        WEAPONENTNAMES[weapon], id, WEAPONENTNAMES[fallback]);
#endif
    hideWeapon(id);
  }
}

hideWeapon(const id) {
#if defined DEBUG_RESTRICTIONS
  LoggerLogDebug(logger, "hiding weapon for %N", id);
#endif
  fm_setUserNextAttack(id, 99999.0);
  set_pev(id, pev_viewmodel2, NULL_STRING);
  set_pev(id, pev_weaponmodel2, NULL_STRING);
}

stock fm_setUserNextAttack(const id, Float: delay) {
  if (pev_valid(id) != 2) {
    return false;
  }

  set_pdata_float(id, WIN32_PLAYER_NEXT_ATTACK_OFFSET, delay);
  return true;
}

stock fm_getWeaponEntOwner(const ent) {
  if (pev_valid(ent) != 2) {
    return -1;
  }

  return get_pdata_cbase(ent, WIN32_WEAPON_OWNER_OFFSET, LINUX_WEAPON_OWNER_DIFF);
}

stock fm_getEquippedWeaponEnt(const id) {
  if (pev_valid(id) != 2) {
    return -1;
  }

  return get_pdata_cbase(id, WIN32_PLAYER_ACTIVE_ITEM_OFFSET);
}

stock fm_stripWeapons(id, weapons) {
  for (new i = 0; i < cellbits && weapons != 0; i++) {
    new const flag = (weapons & (1 << i));
    if (flag == 0) {
      continue;
    }
 
    weapons &= ~flag;

    new const eWeapon = fm_find_ent_by_owner(-1, WEAPONENTNAMES[i], id);
    if (!eWeapon) {
#if defined DEBUG_STRIPPING
      LoggerLogDebug(logger, "weapon ent %s not found!", WEAPONENTNAMES[i]);
#endif
      continue;
    }

#if defined DEBUG_STRIPPING
    LoggerLogDebug(logger, "forcing %N to drop %s", id, WEAPONENTNAMES[i]);
#endif
    engclient_cmd(id, "drop", WEAPONENTNAMES[i]);
    
    new const eBox = pev(eWeapon, pev_owner);
    if (!eBox || eBox == id) {
      continue;
    }

#if defined DEBUG_STRIPPING
    LoggerLogDebug(logger, "removing %s (%d) from map", WEAPONENTNAMES[i], eBox);
#endif
    dllfunc(DLLFunc_Think, eBox);
  }
}

resetWeaponRestrictions(id, bool: logEvent = true) {
#if defined DEBUG_STRIPPING
  if (logEvent) {
    LoggerLogDebug(logger, "resetting stripped weapons for %N", id);
  }
#else
  #pragma unused logEvent
#endif

  allowedWeapons[id] = DEFAULT_ALLOWED_WEAPONS;
  fallbackWeapon[id] = DEFAULT_FALLBACK_WEAPON;
}

setWeaponRestrictions(id, weapons, fallback, bool: strip) {
#if defined DEBUG_RESTRICTIONS
  LoggerLogDebug(logger, "restricting weapons for %N to 0x%08X", id, weapons | fallback);
#endif
  weapons |= (1 << fallback);
  allowedWeapons[id] = weapons;
  fallbackWeapon[id] = fallback;
  
  new eWeapon = fm_getEquippedWeaponEnt(id);
  if (pev_valid(eWeapon)) {
    onItemDeployPost(eWeapon);
  }

  if (strip) {
    new const arsenal = get_user_weapons(id, junk, num);
    new const weaponsToStrip = (arsenal & ~weapons);
#if defined DEBUG_RESTRICTIONS
    LoggerLogDebug(logger, "stripping restricted weapons for %N 0x%08X", id, weaponsToStrip);
#endif
    fm_stripWeapons(id, weaponsToStrip);
  }
}

/*******************************************************************************
 * Natives
 ******************************************************************************/

//native cs_getAllowedWeapons(const id);
public native_getAllowedWeapons(plugin, numParams) {
  if (!numParamsEqual(1, numParams, logger)) {
    return 0;
  }

  new const id = get_param(1);
  if (!is_user_connected(id)) {
    ThrowIllegalArgumentException(logger, "Invalid player id specified: %d", id);
    return 0;
  }
  
  return allowedWeapons[id];
}

//native cs_setWeaponRestrictions(const id, const weapons,
//                                const fallback = CSW_KNIFE,
//                                const bool: strip = false);
public native_setWeaponRestrictions(plugin, numParams) {
  if (!numParamsEqual(4, numParams, logger)) {
    return;
  }

  new const id = get_param(1);
  if (!is_user_connected(id)) {
    ThrowIllegalArgumentException(logger, "Invalid player id specified: %d", id);
    return;
  }

  new const weapons = get_param(2);
  new const fallback = get_param(3);
  new const bool: strip = bool:(get_param(4));
  setWeaponRestrictions(id, weapons, fallback, strip);  
}

//native cs_resetWeaponRestrictions(const id);
public native_resetWeaponRestrictions(plugin, numParams) {
  if (!numParamsEqual(1, numParams, logger)) {
    return;
  }

  new const id = get_param(1);
  if (!is_user_connected(id)) {
    ThrowIllegalArgumentException(logger, "Invalid player id specified: %d", id);
    return;
  }

  resetWeaponRestrictions(id);
}
