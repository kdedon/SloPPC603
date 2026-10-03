#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Fetches the benchmark sources at pinned upstream commits into
# toolchain/build/demo/src and checks each file's SHA-256. Nothing fetched
# here is committed. Files already present with the right hash are kept.
#   Dhrystone 2.1: https://github.com/Keith-S-Thompson/dhrystone/tree/66bb9df1a5dea67f33437b856bf68ae52bd5c90f/v2.1
#   CoreMark:      https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777
#   nbench 2.2.3:  https://github.com/toshsan/nbench/tree/592e671e0c21760f0eb0add1bba50fe7766c1129
#   Embench-IoT:   https://github.com/embench/embench-iot/tree/0466a18e4f6b47e19598d7c6ba72916d54b68f65 (embench-1.0)
#   soft-fp:       https://github.com/gcc-mirror/gcc/tree/2ee5e4300186a92ad73f1a1a64cb918dc76c8d67/libgcc/soft-fp (GCC 12.2.0)
#   libm:          https://github.com/kraj/musl/tree/0784374d561435f7c787a555aeab8ede699ed298/src/math (musl 1.2.5)
#   Whetstone 1.2: https://www.netlib.org/benchmark/whetstone.c as archived on 2024-12-29
#                  (netlib keeps no revisions; the archive snapshot is the pin)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/build/demo/src"
host=https://raw.githubusercontent.com

fetch() {  # dir url-base file sha256
  out="$dest/$1/$3"
  mkdir -p "$(dirname "$out")"
  if [ -f "$out" ] && echo "$4  $out" | sha256sum -c --status; then
    return
  fi
  curl -sfL --retry 3 -o "$out.tmp.$$" "$2/$3"
  if ! echo "$4  $out.tmp.$$" | sha256sum -c --status; then
    rm -f "$out.tmp.$$"
    echo "fetch-benchmarks: $1/$3 does not match its pinned SHA-256" >&2
    exit 1
  fi
  mv "$out.tmp.$$" "$out"
}

dhry="$host/Keith-S-Thompson/dhrystone/66bb9df1a5dea67f33437b856bf68ae52bd5c90f/v2.1"
fetch dhrystone "$dhry" dhry.h 73be10649f198698cf40a48659d079123e45ef2542d275e6885427e4eb10d503
fetch dhrystone "$dhry" dhry_1.c 958069f6ff8fe099ac6121d5f590fa8207bc32a744f138be721bc7358d143cbb
fetch dhrystone "$dhry" dhry_2.c 7954383013caead70e8283375b249ecbaa1aaf092b526acbcac3f187a015c108

cm="$host/eembc/coremark/1f483d5b8316753a742cbf5590caf5bd0a4e4777"
fetch coremark "$cm" coremark.h 42642b9a06c7ed2b3bd9eda971b7c3868c4f5d27bf7ef6c4bba11291a0c2598a
fetch coremark "$cm" core_list_join.c ca00e4e010ece47d7f040cb92aa50a95345a00d3171b59d088f6b243be06ce7b
fetch coremark "$cm" core_main.c 17884c93c5b94378eb0ff02b4df3725756cf2addb9b8cbcaa6200a4649ff5ca7
fetch coremark "$cm" core_matrix.c ecdff717b5a5c4907d221a606760e25499899cbf617582c05d40db71c91351e4
fetch coremark "$cm" core_state.c f4b84bb0a3452c45a4daa664ab502bfdccbd31cb57d93e9ac490c60937717a4e
fetch coremark "$cm" core_util.c a3fbfcb9bb943b638624b8ece01c5836dd56a96d7bcde2697b248d077447327f

nb="$host/toshsan/nbench/592e671e0c21760f0eb0add1bba50fe7766c1129"
fetch nbench "$nb" nbench0.h a7ef94d0445cbdb5e5cb3b3556f1fce497225c2553976dcf43151c84569085d2
fetch nbench "$nb" nbench1.c ab47bc414f42846afc44c3113cd1a88b9e0b8c266bf7038ef88cdcc6ba84680a
fetch nbench "$nb" nbench1.h 62fed9275e6396d73f1fc9085d5a05ba4c407536e4a87d1bf46816193e8c0705
fetch nbench "$nb" nmglobal.h 4ac3cb5a007f80d02036c7a000575b5f1dce5a63b390da16d23a94438fcd8a07
fetch nbench "$nb" emfloat.c a191ffbe501e9a172e158b8f91c120526569c411628019567fc2a1ab4e915e07
fetch nbench "$nb" emfloat.h 6e4eef578cf446b357548b475f74b9eb0af617c5c408563ed50520ff06fd34e0
fetch nbench "$nb" misc.c 195ccdd61d6a3c5c12a04454f6587ac322122f88b7c86637506b6e1ba426950b
fetch nbench "$nb" misc.h c3773c274ded32ed408cf00e1caad5f59049acf9ca64ecb092338e2d70d1e726
fetch nbench "$nb" wordcat.h 5823ea38c42265faac934ab592dec171eed21436596a9c573f59a2be9f0ca039
fetch nbench "$nb" NNET.DAT 4da4898bd5114a9b2c605db3c7d67fcc0fc2e7d87f042fe66158a562bdfba58f
fetch nbench "$nb" README.md 6a44b497ce6d9eb761e2649ee87c8dfbb4c059af306d53ec7bd2d7795d0a9f91
emb="$host/embench/embench-iot/0466a18e4f6b47e19598d7c6ba72916d54b68f65"
fetch embench "$emb" README.md 12974127fc82244562f287882479add20cf3454ca3c5531102f97ba6d97c4238
fetch embench "$emb" COPYING 3c3099e7c092d71a81f14eae5322365afdb2aae1f3d84ff23a41e4ec0b74176a
fetch embench "$emb" baseline-data/speed.json 1ce7b2c86b36eef49e4cb422be0e3ab934cd99526caa8ec00525cf683b12c277
fetch embench "$emb" support/beebsc.c 4fa588eefa678fa89b16f2b898970cfed162845bd494fa47e619fa636ff5d1e1
fetch embench "$emb" support/beebsc.h 9a9fdef180978ec3caa6531d3c2dc6823bc5387731b568402c6c65442a2d7c6c
fetch embench "$emb" support/support.h 3c0862b8279c8d01951b2c8a180f04bd996431c2fb63ffb91773e38895f25e53
fetch embench "$emb" src/aha-mont64/mont64.c e18ee3f518de0431597a16cf27c27c08dba9a540f45ecc9e9ed13956e4f1eb49
fetch embench "$emb" src/crc32/crc_32.c 8180991358e28507a14426207840ec5c340e2491beac8e72658b3832621efb9c
fetch embench "$emb" src/cubic/basicmath_small.c 9c6e07fef13af99e4c225299ca7623ac6889f35ab70c05d92355a4a48c8c82c2
fetch embench "$emb" src/cubic/libcubic.c dfbd2621ed65dbd7313a7ef5b1063799f20839219b298686b7eed2efbcfdee69
fetch embench "$emb" src/cubic/pi.h a85e73070dbd8f87d96fb75c189afd96e20f645b7bd93c04e26cf6831aec02ac
fetch embench "$emb" src/cubic/snipmath.h d16b9fbcb53bd7ed14bf9b2d04c041ff5e0e47727284ac5175965cc4d09c006e
fetch embench "$emb" src/cubic/sniptype.h 6e1d83b87f51034d8154f3b0e89d33005cd53e68add6148556ddfb963554c23e
fetch embench "$emb" src/edn/libedn.c e94f8a6707d37be7cf6b5ed2227903da41988cfcd3ac145b791c756714420ff5
fetch embench "$emb" src/huffbench/libhuffbench.c 434e963c92f3e43a53e71b61020ac1216255a6ba3a4d2c00a206f46b61eb5f85
fetch embench "$emb" src/matmult-int/matmult-int.c d070416c56a5fe1c66ae8f16ca10f59e7c0002a6dbd62ff1db633914220f959d
fetch embench "$emb" src/minver/libminver.c 1840042f2bc683f5bb373aaf9c9441a3dac2a9080aa812384d455b7416243662
fetch embench "$emb" src/nbody/nbody.c ae4aa56e7cf9c65cc7a74ab974ec756c40d36c5785b382c600bd5117096efb6f
fetch embench "$emb" src/nettle-aes/nettle-aes.c 87cd050b8e7eb603f2a15ad1eaba00333915fd1ab3e2d3d3d1b540fa3476f296
fetch embench "$emb" src/nettle-sha256/nettle-sha256.c 2770ad46ac26fac096821eb3ae558364600bdaeb6d96bc06049327c90138959f
fetch embench "$emb" src/nsichneu/libnsichneu.c e4515f435c8d8d13c13f9a7204536a376527f3fbe2737803d8f16d0a0a3747d6
fetch embench "$emb" src/picojpeg/libpicojpeg.c 72cfb201379ccbb943d10334b941f91413a5bf4213cbf75f1657aa3492e5e103
fetch embench "$emb" src/picojpeg/picojpeg.h 50dbd519c3e7b5732cc2e58d9e47195a3e5652f5d14f9d997f102b844e64db36
fetch embench "$emb" src/picojpeg/picojpeg_test.c d41425baf9bafd7d07c7a6656d4bf9678d7b85a4b5d4aa93cacda56a3a29d097
fetch embench "$emb" src/qrduino/ecctable.h 54e176fa47d4c20baab098962a0c0f1a8629362499dbc8fbab5d581312b1002c
fetch embench "$emb" src/qrduino/qrbits.h af772ed9bd01daab613ed2161c47fd065a92ff4932765ab65bfd9877b48af609
fetch embench "$emb" src/qrduino/qrencode.c 05d2147e1809578fcdce4ebd6105a555e59dc8c9b5c5b2f4d7a239ea8d9bf5b8
fetch embench "$emb" src/qrduino/qrencode.h 0e53eccb11ab127e3e6d54bdc66a3d2d5fdb213b937b18d20f7ffe6d890799c3
fetch embench "$emb" src/qrduino/qrframe.c 3d3400ff94ba165d0cf2945a364527f55291fa144511e0a94f317fdc58992f15
fetch embench "$emb" src/qrduino/qrtest.c 6b09aa24d48344494f75187cb3854b891dcbd537a3cbede182d85457a62acabc
fetch embench "$emb" src/sglib-combined/combined.c 24058cbcc06ac1ed679442ab8fced3782e92eefdb7b82947c4537c13a31d0f1c
fetch embench "$emb" src/sglib-combined/sglib.h fb3f51027b228ef863803fe3086dfb9a769a76e6e3016dc0cca826952bb03bd7
fetch embench "$emb" src/slre/libslre.c fb2f84e5133b60655fa7e3a72a6128e63dadd53408fdf38eff5a2ed1732c014d
fetch embench "$emb" src/slre/slre.h 87bdc34b18e269c46c13c3e221f2618fa2aac2b4299fe59561810522880e3264
fetch embench "$emb" src/st/libst.c f04afbb2c3786c86db51094e65db0c4e8d39aee7521c0fd7fb729d7fdac51818
fetch embench "$emb" src/statemate/libstatemate.c 0522d5a9b7502a8f78e5210a35df9ba0e31874d77b22bb7e56e47fce9bc0f3c9
fetch embench "$emb" src/ud/libud.c b03de5ab8657c509a1d314725a0f082f512047b32b5bbd82e9cdbc1f4133d37d
fetch embench "$emb" src/wikisort/libwikisort.c 9fe2e014b0fc8270264722cb680f010f7ae654dfbdd485b66f61e73fdb961471
gcc="$host/gcc-mirror/gcc/2ee5e4300186a92ad73f1a1a64cb918dc76c8d67"
fetch softfp "$gcc" libgcc/soft-fp/soft-fp.h 90585ae86e99688a70b0b4f87297ad32baf48aadf8c849c2f93f1fc89976bcb4
fetch softfp "$gcc" libgcc/soft-fp/op-common.h 3b2cf7c98d20aec46596cb5431985c828cd941f938bbaaef34dd31601007c75d
fetch softfp "$gcc" libgcc/soft-fp/op-1.h 9c886eadb5b7bc25ac4646ea02836ae99e3d965288337b62141131358daba518
fetch softfp "$gcc" libgcc/soft-fp/op-2.h 0b332d122ee63788d53501089aa6ba3b51eecf463d1ac6b82cf48e6ea088baaf
fetch softfp "$gcc" libgcc/soft-fp/op-4.h afc9df5111d4589603a264cd45a72dc6e97d78ad3f2e2218a35f254644dbfd69
fetch softfp "$gcc" libgcc/soft-fp/double.h 3e6c938bfd940abacfc571a852be06fdc6116fd3a1bbf6b2f79b0dd08a1a2644
fetch softfp "$gcc" libgcc/soft-fp/single.h c05e45873e3750b6bf609bb7a798e87d07bbd509572bcc87fa8bd661e5537710
fetch softfp "$gcc" libgcc/config/rs6000/sfp-machine.h 13bfc0bdeaa022359766f1e5cb6d72207146b0dba2dcbe490a2f955bda342930
fetch softfp "$gcc" include/longlong.h efaa9996996a392ebd2e6c132baac411687955d98241845db128d7f6afc4515b
fetch softfp "$gcc" COPYING.RUNTIME 9d6b43ce4d8de0c878bf16b54d8e7a10d9bd42b75178153e3af6a815bdc90f74
fetch softfp "$gcc" libgcc/soft-fp/op-8.h c14a0657e574b1c3dd884eb3e02258b05a3c4e8f8ab3b8bf5e60abcd07fc69ce
fetch softfp "$gcc" libgcc/soft-fp/adddf3.c fe359d729823c48a02d78af91f455e573ee152a38fe9e4f4db7ac1aa3760e9d0
fetch softfp "$gcc" libgcc/soft-fp/subdf3.c 4649988e732a6cce7cda7cfc78868aa0d644399a4c3c5377582768897c101876
fetch softfp "$gcc" libgcc/soft-fp/muldf3.c 562895cbc6e7791a27c10bb0acda686ef3404bf5c974295dce47d2cc2a89d06d
fetch softfp "$gcc" libgcc/soft-fp/divdf3.c 8ec8ad623c9ce3801e0c4837996b749c4092302435c6d372f8639d24064c1f92
fetch softfp "$gcc" libgcc/soft-fp/negdf2.c 95594f1fd516146b84da6d35f3b4a6d156deeb268fb6d904b6520f120aa05cff
fetch softfp "$gcc" libgcc/soft-fp/eqdf2.c 98d4d7cc9dfbe0a7c14f384a8350a7645727dc7b1176f890fb48adda152694ce
fetch softfp "$gcc" libgcc/soft-fp/gedf2.c bf22cb6834d791f44b5e057fe521d9c92cf37e1c865641bad7c6c7703ad3358e
fetch softfp "$gcc" libgcc/soft-fp/ledf2.c d0d7b190b977e15646a6ee238ed51ba79337f814e8ffb73006f74ae8f94ba5b6
fetch softfp "$gcc" libgcc/soft-fp/unorddf2.c 4e5ef88b473afda53bb5731e71982b54b3bcfda94122fdc45590292dd9dbac97
fetch softfp "$gcc" libgcc/soft-fp/floatsidf.c a42d25e1a1229bd2360f769be27e8391c8d40c3c28c49d3dcdd0c6474eb6368f
fetch softfp "$gcc" libgcc/soft-fp/floatunsidf.c 3f39e0777fb0a7c8d84b1aa67229d03cb83b6a93f55e159da9bb3192d2805401
fetch softfp "$gcc" libgcc/soft-fp/floatdidf.c 51cae6077a062710b2368141fdc31b79595a9a4d46d0e2b36ff30398b628fcaa
fetch softfp "$gcc" libgcc/soft-fp/floatundidf.c b5ea07a6e8e1670fac8446a861d4c8597e17082e2799046c4626e6e1a1be142b
fetch softfp "$gcc" libgcc/soft-fp/fixdfsi.c 626fd50706fc828cefc8c3d397df8d390a52f8b4648e8ff483c474d6ce5dc485
fetch softfp "$gcc" libgcc/soft-fp/fixunsdfsi.c e3db2f4fc63bcc1954e1bf63574cd8f8c7777141e3948b5c2afdc87f4e223a17
fetch softfp "$gcc" libgcc/soft-fp/fixdfdi.c 546aa835c9c26f39062ca9f27e26f8b81469c9fe663a12d64be09f58314b2a5b
fetch softfp "$gcc" libgcc/soft-fp/fixunsdfdi.c 887d677d88a86215daef647eb3cda4bdcd05222003c8251869192b4441fe3844
fetch softfp "$gcc" libgcc/soft-fp/extendsfdf2.c 8576bc8d5c2cc65c523be29304d7bc36c93e9eb803cb168238bc0dc88bd84309
fetch softfp "$gcc" libgcc/soft-fp/truncdfsf2.c b40f8c8bf92b7ce4fe33ca0184f351b1a2e372c983c0c7de67dbe946f623db8a
fetch softfp "$gcc" libgcc/soft-fp/addsf3.c e50699ade4ffff1d916d0703f530c180a493bd55a4b4930f6bb94b424c85e267
fetch softfp "$gcc" libgcc/soft-fp/subsf3.c 28aa00c6b4c92c3195f3037a279d124712a791ea955b2f37cd587e225e1457b2
fetch softfp "$gcc" libgcc/soft-fp/mulsf3.c b85ec88c9280427692a9f99e578f98ac8d63aac4bc4787f995e59abc6ede94f8
fetch softfp "$gcc" libgcc/soft-fp/divsf3.c eb172f7c8200108c80879772767b23ab2ded40b08335984c7ece9b017ba0232f
fetch softfp "$gcc" libgcc/soft-fp/negsf2.c 904bb43b87a3fe8a1333ff2182fbb14c5b9b2579a09d45f5bcbb1605aba3ed85
fetch softfp "$gcc" libgcc/soft-fp/eqsf2.c e0ba929dcfdeee1ae64877c7ecf3b74152b62ba276cc226fafa78c3a8f877407
fetch softfp "$gcc" libgcc/soft-fp/gesf2.c 40b8a89df91bcdfea35b728d0ce31cdc1dc39620fe90d97403c6360b76dd391b
fetch softfp "$gcc" libgcc/soft-fp/lesf2.c 90c8b21ab650acbd7bf637318eb0953000195f3727d998d38daa3bed30f4657f
fetch softfp "$gcc" libgcc/soft-fp/unordsf2.c ca57b16d1a46f50dbf740b2c9738673d07ffc82c4e42b28d1b9a7fad5e465bef
fetch softfp "$gcc" libgcc/soft-fp/floatsisf.c e1c15bbcf9f9c84a55f29cdc5b67d48a33c5f5a61db809c334f484bad4f6fce0
fetch softfp "$gcc" libgcc/soft-fp/floatunsisf.c 8434f4002b7cfdb699c60e98812d1ed0c38ac019714d53dfe40f67d9f935c5c6
fetch softfp "$gcc" libgcc/soft-fp/floatdisf.c 27e82f881f0e1d916603abbd5113c9e1b7732805a3005cb0b3174284704cd262
fetch softfp "$gcc" libgcc/soft-fp/floatundisf.c 56c6768b1cc4747d6d49d2dd32b479d3bacd407c471c61ff7b5048ee563ee346
fetch softfp "$gcc" libgcc/soft-fp/fixsfsi.c 69e0bc03eca382f8eae474ecc4bbd87223fbcf487139fb926aa7e5774b1440c7
fetch softfp "$gcc" libgcc/soft-fp/fixunssfsi.c d1506eee2c148b9c11aaa8570ceb7a202dbdae665ec365cf8945baa2577a329b
fetch softfp "$gcc" libgcc/soft-fp/fixsfdi.c ef17e0aa59fe768012a03db57435591530e1979f7300ff2b6ca0cc1fe7eb72f0
fetch softfp "$gcc" libgcc/soft-fp/fixunssfdi.c d57051a4ab51196280fc13496da976e395920a61c4a8d7af5cd481d02da1d6e7
musl="$host/kraj/musl/0784374d561435f7c787a555aeab8ede699ed298"
fetch libm "$musl" COPYRIGHT f9bc4423732350eb0b3f7ed7e91d530298476f8fec0c6c427a1c04ade22655af
fetch libm "$musl" src/internal/libm.h d5a11757541471030d8f4bf7a39a29de35732ecbb291b2f45bf03296be4f25a2
fetch libm "$musl" src/math/sin.c 24e53a9d85f196f66919cc19247be5480bb607ef38844b1a24bc47c4fe4974ef
fetch libm "$musl" src/math/cos.c 3a74e054057d636fa494bdd76a53a40db5cee618264f6ab31cb0538ba63c6bda
fetch libm "$musl" src/math/__sin.c f3a37ef9bcfb8a2f9c809d8c7f1aa2c17c8c3319ad7fb2fe7c0a6284ea8859d2
fetch libm "$musl" src/math/__cos.c 3f0f774aab60a18d7ef935ffdf121bcda17cbadabff14096c614da22e31a42c1
fetch libm "$musl" src/math/__rem_pio2.c 938329e0939cd83ee2185a52154b41242f618d4a6df1b08395f344da33d4f1e6
fetch libm "$musl" src/math/__rem_pio2_large.c b97f19fb5951c83a0c10506fab35646caefde13bd03100ad2af55ef00af0b9fb
fetch libm "$musl" src/math/exp.c 7db56f21ca9b8915d36dd5099b707aafeb6a736eae798e19b76b074764e75f34
fetch libm "$musl" src/math/exp_data.c c55dff64e369fe816cd8ce367064989bb119f85783599680d1a329031c660689
fetch libm "$musl" src/math/exp_data.h df77fca837edd02b260dd09a2914202775909ae67a059218ae38cfab104e6d16
fetch libm "$musl" src/math/pow.c b06f0a08d74fcff8cced7afa2c0e47e301e3e8a19c0de5becdec28cd7b014027
fetch libm "$musl" src/math/pow_data.c 2052ec913f9b4a2170a98a6fcbcd7694f5dec220036b00c36106a2b4b65a4c55
fetch libm "$musl" src/math/pow_data.h 5014345a7958adcf6ff835b5e96afa99dd5a98c40dfe968442288e002b8e01a3
fetch libm "$musl" src/math/floor.c b9ccb9363719a84be218d60c56717f4fb0234e170c305e36ce21c30e1f42f8e1
fetch libm "$musl" src/math/log.c a0694d8587a0d145d0f8ae87cbffba014d7988bc2ebcbfad94cea73b394c9ecc
fetch libm "$musl" src/math/log_data.c e96bcd99d88fc57e0f3686299014f4b949a6212603ce237f39e16cedc155617a
fetch libm "$musl" src/math/log_data.h a8dced6f0821f30cad040ba326b03e419fbe0a750ed8f3b0d7145992bee4bccc
fetch libm "$musl" src/math/scalbn.c a2e766283ed30c2b30c71e01dbdabef58faf92cc9aa84a01c1ce1069b6625696
fetch libm "$musl" src/math/sqrt.c 688908f94c3edf7a439cb64094034a596a1fbff08445b9158a22874cb52ead4f
fetch libm "$musl" src/math/sqrt_data.c 590aaadff964dcfc36ef9e5302423a779cda4f1608e15dbeee8e43e6e5f1c6fe
fetch libm "$musl" src/math/sqrt_data.h 5fa47a8b8c1afbee4dcd10f71d2f6c433a24f9aa5ce7a90924cd1db236cbc03c
fetch libm "$musl" src/math/fabs.c 99880a7802d67077fa54a2bbb5d3388cf42b00c96d3e2b1c16d63f2918157754
fetch libm "$musl" src/math/acos.c cc6f9017e7e2e0ef01516fa12c68aa63865e6415c90dc039dfce9abffae09a4c
fetch libm "$musl" src/math/atan.c 1cffb67a65456ae0bc5f07a94df04a4f18ebc1ac0bffe3219250c4e0555ee01d
fetch libm "$musl" src/math/__math_oflow.c 74669de53bc4b250183cfa262a8a03ee8106f33a83e3aca6b217bafc7363b83c
fetch libm "$musl" src/math/__math_uflow.c 9a841197bbe9ade9bbd684f8bc65424a97c481d37dabb9fa1790bafe7959034a
fetch libm "$musl" src/math/__math_xflow.c 5feafe10347636884a071a5096f912d5ca4a0939844804ca09b88241405648ad
fetch libm "$musl" src/math/__math_invalid.c b56440ed59fa1e1aaaf6bf8b672c8bb71eaf844457906f7773da1d67d7ef013b
fetch libm "$musl" src/math/__math_divzero.c 84aa910bdc5e7ccfed42098c37c44e278aa942d46e5a51d5ee8273336c79e719
whet="https://web.archive.org/web/20241229210241id_/https://www.netlib.org/benchmark"
fetch whetstone "$whet" whetstone.c 333e4ceca042c146f63eec605573d16ae8b07166cbc44a17bec1ea97c6f1efbf
echo "fetch-benchmarks: sources verified in $dest"
