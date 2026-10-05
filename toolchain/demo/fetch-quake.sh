#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Fetches the Quake benchmark's inputs at pinned versions and checks each
# file's SHA-256. Nothing fetched here is committed; files already present
# with the right hash are kept.
#   quakegeneric (GPL-2.0): https://github.com/erysdren/quakegeneric/tree/13052102577c629650cf07a46151a4b6e1b19c3c
#     into toolchain/build/demo/src/quakegeneric
#   Frank Wille's Amiga Quake 1.09 v2.30 source (GPL-2.0: "Quake is published
#   under the GNU Public License", QuakeMOS.readme of the same release):
#     http://server.owl.de/~frank/quake1/2.30/Quake_src.lha and QuakeMOS.lha
#     into toolchain/build/demo/src/amigaquake, the PowerPC sources unpacked
#   pak0.pak, Quake v1.06 shareware id1 (id Software; redistributable
#   unmodified only):
#     https://github.com/pweil-/origin-quake/blob/45f9279d81577cdf6a018277b200683ec75dac98/id1/pak0.pak
#     into toolchain/build/demo/pak/pak0.pak
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
host=https://raw.githubusercontent.com

fetch_to() {  # out url sha256
  mkdir -p "$(dirname "$1")"
  if [ -f "$1" ] && echo "$3  $1" | sha256sum -c --status; then
    return
  fi
  curl -sfL --retry 3 -o "$1.tmp.$$" "$2"
  if ! echo "$3  $1.tmp.$$" | sha256sum -c --status; then
    rm -f "$1.tmp.$$"
    echo "fetch-quake: $2 does not match its pinned SHA-256" >&2
    exit 1
  fi
  mv "$1.tmp.$$" "$1"
}
fetch() {  # dir url-base file sha256
  fetch_to "$root/build/demo/src/$1/$3" "$2/$3" "$4"
}

fetch_to "$root/build/demo/pak/pak0.pak" \
  "$host/pweil-/origin-quake/45f9279d81577cdf6a018277b200683ec75dac98/id1/pak0.pak" \
  35a9c55e5e5a284a159ad2a62e0e8def23d829561fe2f54eb402dbc0a9a946af

aq="$root/build/demo/src/amigaquake"
fetch_to "$aq/Quake_src.lha" http://server.owl.de/~frank/quake1/2.30/Quake_src.lha \
  f61211db6e16b277771a79e6e2d2f41b100301293c9aa5e0b99c355f42c50d30
fetch_to "$aq/QuakeMOS.lha" http://server.owl.de/~frank/quake1/2.30/QuakeMOS.lha \
  ef7a1be41c67b05a52354912002e7520c1821d2c4db0ffde29988560ff7975d8
python3 "$root/demo/lha.py" "$aq/QuakeMOS.lha" "$aq" QuakeMOS.readme COPYING
asm="d_scanPPC r_surfPPC d_polysetPPC d_edgePPC r_edgePPC r_drawPPC r_aliasPPC r_aclipPPC d_skyPPC
  d_surfPPC mathlibPPC r_miscPPC r_bspPPC r_lightPPC fconstPPC"
python3 "$root/demo/lha.py" "$aq/Quake_src.lha" "$aq" Quake/macrosPPC.i Quake/quakeasmheaders.gen \
  Quake/genasmheaders.c $(for f in $asm; do echo "Quake/$f.s"; done)

qg="$host/erysdren/quakegeneric/13052102577c629650cf07a46151a4b6e1b19c3c"
fetch quakegeneric "$qg" LICENSE 8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643
fetch quakegeneric "$qg" README.md 16d2c6e172798133c6508cea64e73c1b5acd031655bdc60d013797a32dfc6935
fetch quakegeneric "$qg" source/adivtab.h 06a327cee06d95748f772f48424dc8b48949778050cb452d17a03e33c9100e6f
fetch quakegeneric "$qg" source/anorms.h 1d21f2e9c1ff6cb704ade4f04206cbc1aaadb6930370bb7d54a63c469eb9ee65
fetch quakegeneric "$qg" source/bspfile.h 7765b458a744879b253020f5039d7ed950fe52b2a0945ebfdd2f1027f53db700
fetch quakegeneric "$qg" source/cd_null.c eb41e859a476a2f49824d425ab55d0cff65ae91819efa51a72db344c4b5be5cf
fetch quakegeneric "$qg" source/cdaudio.h 8bb410e536d6ce0e077cf229bc5fb77cf7ae7501d2e71179ee4211b5cd7c0207
fetch quakegeneric "$qg" source/chase.c 468d930ea3b2f3cf2b6a33921b636ef04ac1a978045128d816881364471b86a5
fetch quakegeneric "$qg" source/cl_demo.c 91e69fe8be5cc8c7c26fc483815dc6be0035d7a59a51b63946b4ea53fa1aa40a
fetch quakegeneric "$qg" source/cl_input.c 0abece7eb8863e53858b263c2552fc34209ab884b7f353602d5d41eebbe2fd99
fetch quakegeneric "$qg" source/cl_main.c 71675b9966bee4111dc570771d8242a1b272818a33c42af7541b5ddeb9752ed1
fetch quakegeneric "$qg" source/cl_parse.c 6d61a517b3511739074920c4c01296f5a0327fb1d1458adc9737af0205cd5aa0
fetch quakegeneric "$qg" source/cl_tent.c 1b1df7061d3332908afe9c7bf3ab4b509b2c4ef688ac2f37c12202ae3b50250e
fetch quakegeneric "$qg" source/client.h 4bdf3a952ce2a0886816dfc552b031a39cc7b9b98ffec8ee600f2d21c4059394
fetch quakegeneric "$qg" source/cmd.c d61003668f8586aaa629c13ed8d979d692606230eb30c59f80d1c3024dd8edb9
fetch quakegeneric "$qg" source/cmd.h 99ca99629e32c7711da8fe15d775257db3c2e82ed002527700fc7d87caf2d1a3
fetch quakegeneric "$qg" source/common.c c12057b1c7203b36eb160946e9e410b19cd7a90ea9a745e1f675d98cf31643eb
fetch quakegeneric "$qg" source/common.h 58380f5ce4de4cbbc63605de4fb4924e149f1d6923727a7e499b3035b31863b9
fetch quakegeneric "$qg" source/console.c 4fc680a883e0e092724a23711149be137b7095fba647c57c0951daa59a860052
fetch quakegeneric "$qg" source/console.h 6a3165abff55e700b336231482d0f91807ecaa5b92f43be9619d3ad700ef36cd
fetch quakegeneric "$qg" source/crc.c ace65596615c564a62cf998d925d9457cb20dbf412c26eed4f1aedf3d77dacd1
fetch quakegeneric "$qg" source/crc.h cc7b9d14b3d7cbaf5c59226243d9f882a3396440a9ed905ccee6d84256c55798
fetch quakegeneric "$qg" source/cvar.c cd381320c10e85a4a0a4b3ec5c254326a77172bf58c1dfb92354cce8000b39cd
fetch quakegeneric "$qg" source/cvar.h a7c534e9aba9e9f618f09a5c901b815e6a5ff4d582fdeb4046f71c17005d5efa
fetch quakegeneric "$qg" source/d_edge.c 7b0071fbb15b335b3250760eae3f301b7017ef4787b9ec0aa5119591c64089c9
fetch quakegeneric "$qg" source/d_fill.c c9e57957f56cd95601e5b5db48f3d85ae79f4a831ce5b3883e4b02603b3a40fc
fetch quakegeneric "$qg" source/d_iface.h 85036544d61c013f514964e34d0045fdb3b75bcfd706d0135b0136515f3b00e8
fetch quakegeneric "$qg" source/d_ifacea.h d6093ccdd43de7397c9eec38bcc6e87004a3cc1c5088e78d91786706022234d3
fetch quakegeneric "$qg" source/d_init.c 953713481fcaa7e1a4b94867df12ad12ccf92f117bf90ba8979feaa429f30a1e
fetch quakegeneric "$qg" source/d_local.h f0c2276074891ecaf0aa83e3bab0283aacbc28dc05908a7e55f7523bee83fbef
fetch quakegeneric "$qg" source/d_modech.c 5e470f3ec68f39daa2ab35a8a01d964ad886a7fc21d8c42be0156984f8a78ecb
fetch quakegeneric "$qg" source/d_part.c 827236cbcaa039652a9a25d0f2d7dd4abe5765a3cec239124b41076fb3d9a7ec
fetch quakegeneric "$qg" source/d_polyse.c 7bd31cf589e5ea9b1b2a4e68f5f11a94334009dc9adb2eb09a7852163c03f40c
fetch quakegeneric "$qg" source/d_scan.c 2057698b6930ad2280ba040a9390e37bdb75fbd08a8cb5289fe8cf9080fe65da
fetch quakegeneric "$qg" source/d_sky.c 7267d7454e04b999e15c56e7b802c8721ec28daa07f247427d79cc169fe19b3e
fetch quakegeneric "$qg" source/d_sprite.c 7159be593ff80ac29f52a2004b9b3d1a6bc5b052b5b7261791180f0239cb334a
fetch quakegeneric "$qg" source/d_surf.c b7d4f8607bfffc61b4127a10a6dd279a0f6f9a651eeede40cebe153137583914
fetch quakegeneric "$qg" source/d_vars.c 365d11dfa2ec73cff7d65e9adb63a5af679f792e4a82b4a63458db378735255a
fetch quakegeneric "$qg" source/d_zpoint.c 40a258b1afd20ac280f56e61fd6f946bf8d864d57c3142a2e59e485170720848
fetch quakegeneric "$qg" source/draw.c 6d5dbbb1ed6da6b5e41a460b1f5ee2bb66aa5125f34848f5308c424bb068c9a4
fetch quakegeneric "$qg" source/draw.h 5a661fd88e0224ad59353dd9024f135089337ca7fcea0188159cc37442d3e674
fetch quakegeneric "$qg" source/host.c 96dc6b4b2be2efed6f93f3d344f2dcdead46a5d5575ba97e3fcc38d975e0938e
fetch quakegeneric "$qg" source/host_cmd.c 51d821b2f48c23c9acab6cc513cf662458a96ec2428cb34641894079c09fe861
fetch quakegeneric "$qg" source/in_null.c eec222d31601d1172f46bb693f059164e7271ff9f91571f434c2543dec506556
fetch quakegeneric "$qg" source/input.h 21f3c6ff84db0edd35ecfc446891d6e0003ffe34d487c94e498a9bf58da5a39e
fetch quakegeneric "$qg" source/keys.c eb7582d1a5777fc8ffb02a4039b3e390e471575111c4969ed73fbbd67f9ca647
fetch quakegeneric "$qg" source/keys.h 5596150585d8614139f2b7187902e2f61dfe5a00358413adc5406374e86c1017
fetch quakegeneric "$qg" source/mathlib.c 8b909842358cac82824802278c7d23b3d39f8feccf8621c615b63438d6537c8f
fetch quakegeneric "$qg" source/mathlib.h d738ca0d4a2c0179b552854481afb324004d95e3fe578ce9fd7c2eed0a5afc87
fetch quakegeneric "$qg" source/menu.c 5e33fc7aeaeff4124d6c90a9906d29031737ae92fff4e3edcc1cdb5f21f17a6f
fetch quakegeneric "$qg" source/menu.h 404ce3e8d39bc91a04754faff7866cbf48c7416612a1dd19fdea4d894f04074d
fetch quakegeneric "$qg" source/model.c e7a9cc2b2af8d3062b8a26e0c3a535649165381c0047a60551e0bfb2df8d1b08
fetch quakegeneric "$qg" source/model.h 61048ae2f29de24f09618b6b1a0552d078a0b1799a7b6caa684dddd8d72186a3
fetch quakegeneric "$qg" source/modelgen.h 1af78ac12387e348df2da0ddcc85c8ccbe3870da159bb86f74a60d69cca04fda
fetch quakegeneric "$qg" source/net.h 37e9efcf383df3afe8589bcfca1055ac5110745471bdce41e96bcae7136d2289
fetch quakegeneric "$qg" source/net_loop.c 174bb5c02a8cc07b239cbd7376a3253d91229d44b5acdd81c68f9c6f019889b8
fetch quakegeneric "$qg" source/net_loop.h b10db09189ec85b36be6b782022b641363678167e8a1cb0b7d6bac98b9090f45
fetch quakegeneric "$qg" source/net_main.c c2dc539c93765e50a2de49b1bfd6fa32cea5dea1e99f1a9026df0599b9a7383c
fetch quakegeneric "$qg" source/net_none.c 2c19f3b601c0fd8e3bde4ac50f51ac204713272f11e9fe3b068c8218bdc29bfb
fetch quakegeneric "$qg" source/net_vcr.c 68928690ebdfcdd6289f3855d5abe04de4690834e7832c6b977be0234e6e758d
fetch quakegeneric "$qg" source/net_vcr.h 7ca130f0ab94e56db4b41108559f8742a27441a574b2e1cc7954b448ca98eac7
fetch quakegeneric "$qg" source/nonintel.c 52e50ffe3659e1fbfc43d4e2fa7b57b758ecb6018f07b26a6458533e7d5f251a
fetch quakegeneric "$qg" source/pr_cmds.c 878d7644dba2f2f80e27ca4622306691785fec2dac8025044ede74b2e60db645
fetch quakegeneric "$qg" source/pr_comp.h 30c8f32cb84bdb6ab31b79873390526e4a7bcc56ee14ea2b6b98dc274f5639ff
fetch quakegeneric "$qg" source/pr_edict.c 97da745b0f498446c84b2b8fbf19385b412d1b58290c38c87e03e7bb334729e8
fetch quakegeneric "$qg" source/pr_exec.c 6cfc54e30fc99e63b6c77e705419a7fe23020b959d79396134628952c4d28b21
fetch quakegeneric "$qg" source/progdefs.h 16622583aa637bc12e998b59302e7653669c77742a1e7b2318221e0485da8fa0
fetch quakegeneric "$qg" source/progs.h 2ba22bcae0bf4915970876e902064448c4191653968b3a2a2c5bdfade8005596
fetch quakegeneric "$qg" source/protocol.h 000665c156ca5da011d87f5b941ed7331cc1726e46589e20995953cb372acae3
fetch quakegeneric "$qg" source/quakedef.h b34d5db366b63c19f78fe3be22a9398526d515d0d9551b5643e9e292488b2517
fetch quakegeneric "$qg" source/quakegeneric.c 4a5ddd8101df58aa10d776808222fb7c430de4510c376e0c4e5c6aba8db444ad
fetch quakegeneric "$qg" source/quakegeneric.h 11bb53d63b94023d3c6970035ee06e465b491654242906f8955640462dfcdf54
fetch quakegeneric "$qg" source/quakekeys.h b8c17830d6d388980164c0d0557c0dc2494d23cd9cc9326f1e70ae9c230e464c
fetch quakegeneric "$qg" source/r_aclip.c 0cdfbffcf208f28254fa2c30ba6554622de373414999f3fbf7a159377d14730b
fetch quakegeneric "$qg" source/r_alias.c b0ce281038b4ce97d52095283ae1702f2e38ff7c01a7865ef96f6f3b2a9ed7a6
fetch quakegeneric "$qg" source/r_bsp.c f0c527a136c8e8e1ff373f0dc2e1980a5a2694c83e12c9e92be39f36fa3489a9
fetch quakegeneric "$qg" source/r_draw.c 3c1e36548656907c188be0f3e2d8175df919029cb5752e2620aa767a2d51de2f
fetch quakegeneric "$qg" source/r_edge.c 097ad38e85fb8677b4ab147c83a2b2854b63ea53426e58e36a16223fd2f352a1
fetch quakegeneric "$qg" source/r_efrag.c 7922ef83807289740a4d957d81fbba08813e8aa29828122e996ed42a38427613
fetch quakegeneric "$qg" source/r_light.c f71db4a482b7c7f8ad37b02e12b2cb5eba856d026425de43b69c686dacf452d2
fetch quakegeneric "$qg" source/r_local.h 67ac515132ec6ab4484a54e480cb8493a1adebc2e15981c183b91bdfdca62268
fetch quakegeneric "$qg" source/r_main.c ee94a451516d63f0cc964a1456116842ec95b2a8cb866e14bf4f62f66da8469a
fetch quakegeneric "$qg" source/r_misc.c a69e002cebe72259530e38d836935ae952314063e42379e4c1f3900d79421661
fetch quakegeneric "$qg" source/r_part.c d201d20e6235f0397265644ec336a79c60ac764f1ae3c56342d936a81e7ab423
fetch quakegeneric "$qg" source/r_shared.h 43f2394879fcd368967dfe243ac1c916799d826a590cf26f2d4f68d0a3dfc61f
fetch quakegeneric "$qg" source/r_sky.c 1b2a68a0c6fa32c4748d3b90552a67432eb85dbe6caef1a9092c2319883f8138
fetch quakegeneric "$qg" source/r_sprite.c f16660ed5d69398b3972f0f75aec9974508aa8997df7f09d65233ae23f1fe625
fetch quakegeneric "$qg" source/r_surf.c c7a6df6ca89b19d18e588eb813f748ce5f61d1a710d6095c596548462bc8c830
fetch quakegeneric "$qg" source/r_vars.c 1f0e8ccbd6d0f97a5343b004d040bb60d65b0932ed11947c0e58325c407f76e3
fetch quakegeneric "$qg" source/render.h d8a8ad4a9e8f314091eeca10dc04942e70ed598e2a644d9f0e54085b1d6a043b
fetch quakegeneric "$qg" source/sbar.c dbe1b3393b33a3d86d25d96ba30a0b192cd935af11ded8844fd7bd0aa06b73a4
fetch quakegeneric "$qg" source/sbar.h 76eb2b6a3cc8f49812b86d758f7790701ab724b3d85a3649c8654f575d32d321
fetch quakegeneric "$qg" source/screen.c 92d102119e83f62691d49094243598ef9c373bf1e422ce752a094bd736308a8f
fetch quakegeneric "$qg" source/screen.h 5b889200a07e3288487b63244a9d04b04d700f0fb13868a0a4821e848bc89997
fetch quakegeneric "$qg" source/server.h ddf9041336d52b78527f1e44b49209e39e2be60473ea768167a22ca322320073
fetch quakegeneric "$qg" source/snd_null.c 3a41baecc2c08ae9478ce18edcf59f582e4d6f05cc280c0b42c458cb7437be02
fetch quakegeneric "$qg" source/sound.h c3d18c65f381b7afdececb6cbed96c14a405516c18e0a0457830c7ba7259ec2b
fetch quakegeneric "$qg" source/spritegn.h f3f707d9c4ccb8963e3aa4c014afa46ea7efc2f7724e768cc41838c18fde52ab
fetch quakegeneric "$qg" source/sv_main.c 7f078154cbcfa7cee6c715910dc517ffe21e83eac82619ecfa4a164738928c72
fetch quakegeneric "$qg" source/sv_move.c dce60d060bb9ede188a8d257765304f22ef3ee0bb406b77a9512d3f04d1fece1
fetch quakegeneric "$qg" source/sv_phys.c d547d6afb612088af5ab46968ee2590a47620667ee6825c1777f1b6ce0dc6355
fetch quakegeneric "$qg" source/sv_user.c 6c7290b3d869938167cb52de931b999f56303cb08f926a572a881e9a39345bfd
fetch quakegeneric "$qg" source/sys.h 1dbd5e878eb5e350010e6955f5e5b7208de887f35216c91ae74f4afb751bb4ae
fetch quakegeneric "$qg" source/sys_null.c b43b9446ccf3ab3cf1e67dff15044a42401832dacf73a877e075f12315e90a7a
fetch quakegeneric "$qg" source/vid.h db6920fff853fdc0ee08b28f50c13cf929273283cbbe1a77fb690a467cfa19fb
fetch quakegeneric "$qg" source/vid_null.c 0ab2d64ab1a9210fc57bbb5251607f43a63fb298141a40f6cb567295de9980d2
fetch quakegeneric "$qg" source/view.c e492810287a2eeda58b7375400214b01a703538129aeae752d3c0f0ea3c8eaa7
fetch quakegeneric "$qg" source/view.h 5534d00f1491479f715969fec20b91e32e41a3af53dbb80ab6208c364b07c803
fetch quakegeneric "$qg" source/wad.c 29447665d1253e1fe73907ba8d3f0c26e825902b05a7c0207829e2e313f9ef29
fetch quakegeneric "$qg" source/wad.h 2791cfc7619069afcfc7f82098b8d2bcbd93216619535bb962a881a528487c4d
fetch quakegeneric "$qg" source/world.c f50fd2aaec220de8382fd72e7ab8cb1360986f730a5905d565d0f76f116ce89a
fetch quakegeneric "$qg" source/world.h 15272f34c7032fbc3e558587336edc28f15dca2041e388b3041185081970110c
fetch quakegeneric "$qg" source/zone.c 67cb8b207c7b2e3b128d4f79f2b5efad7b9bfe95d45da15704974eef42a4032b
fetch quakegeneric "$qg" source/zone.h aec01740b4937228223d3487d8f5fc5e30216055738375c7b605f882fbd6e938
echo "fetch-quake: sources and pak0.pak verified"
