# 本地无窗口回归（Windows）

## I05e-2a private Sally qualification

`test_i05_sally_foundation.gd` is mandatory in the local runner and core CI job. It checks the private server capability, empty/real/hidden weapon slots, gender, Sage restoration and stale/dead/disappeared bodies, plus the real Borrowed Sword target query and a real-weapon positive control (SA-Q9). These are qualification primitives only: no Sally public roster, actual Chixiong trigger, voluntary equipment-discard UI or full skill/network implementation is claimed. Adopted SA-Q1–Q9 are recorded in manual 6.19; later substeps follow the Sally audit. All old suites, assertions and time limits remain required.

## I05d-8 public Simba acceptance

`test_i05_simba_judgment.gd` retains the private skill, AI and lifecycle checks and adds native menu/normal-roster/public-detail checks. The accepted rule source is manual 6.13 plus SI-Q1–Q12; remainder carries inside a round and clears at its end. No new PDF adoption.

`test_i05_simba_network.gd` uses only normal lobby choices, initial dealing and real opaque UI tokens. Kevin's natural Duel/Strike RPS draws supply the other-character extra draws; Simba receives Burning Camp, uses Emergency, repeatedly gives Good Deeds, reclaims the donor's marks during actual dying and receives two real END fee batches. It also checks Wanci's original-card discard, real round cleanup, source/recipient HP and marks, authority/privacy and no forged card USE facts. No HP/hand/phase/mark/identity/clock seeding, no rule/response overrides. Normal public lobby-order choices make the two tested generals adjacent for the handbook distance-1 Burning Camp; the driver then locates actual public generals/space, never assumes client launch order equals seat order. Host/remote, normal/cancel, real 30-second step into reserve, disconnect and ambitious identity profiles retain the 45-second internal/60-second outer limits. Reserve selects a normal decline after observing reserve; full exhaustion is tested by the real timeout callbacks in the mandatory skill suite, not falsely claimed as a 90-second live wait inside a 45-second profile.

The new standalone Simba CI job preserves the four original jobs and all original specs, assertions and 10-minute/120-second/60-second limits. The final candidate also requires all fifteen mode/count configurations plus every existing CI ownership/dragon/mountain/David/Sunny case. Public source is fourteen unique non-placeholder generals and `campus-lan-17`; no EXE is built without a new request.

## QA-T354 / I05c complete public Sunny candidate

The original 2357-assert Sunny aggregate exceeded the strict 60-second normal wrapper in the final matrix. Its existing modules are now partitioned into `test_i05_sunny_reactions.gd` (skills/batches/rewards) and mandatory `test_i05_sunny_payments.gd` (the six original Q12-Q16 parent modules). Module files and assertions are unchanged; the two counts must sum to 2357. Both local total entry and CI require both groups. Total assertions remain 28395; import plus fifteen groups produce sixteen receipts. No timeout, clock or error predicate changes.


`i05_sunny_public_opening_cases.gd` adds 18 mandatory checks through the existing external-loss suite (1117 retained, now 1135). It checks the thirteen-general pool, four-HP data, all default capabilities, protocol 16, real native menu selection, exactly one Filming/Spy action and limited-use state. Previous metadata/pool expectations now describe the public roster; unchanged negative cases still exclude Lucas/Andy. The old reentrant-awakening fixture drives the mandatory answer concurrently and verifies that its joining caller finishes or is invalidated with the original phase.

`test_i05_sunny_network.gd` and `lan_sunny_driver.gd` drive independent ENet peers from ordinary setup and public inputs. A real bow equips unlimited Kill range, a Duel and Kill response injure the source, a real Strike injures Sunny, and Harvest draws a tracked new card. Greed uses actual RPS; Filming pays a real card and heals two recipients; identity modes use Spy through public portraits. Five physical USE/RESPONSE facts complete, no extra skill USE is fabricated, exact hand counts and viewer-specific identities are verified. The eleven CI cases, in a separate job with the unchanged ten-minute job limit, include 3/5 players, host/remote Sunny, cancellations, real base-step/reserve elapsed time, active-window disconnects, and six-player ambitious identity exchange. No hand/HP/identity injection, shortened clock, new LAN AI seat or relaxed timeout is used.

Failure evidence remains in local candidate receipts. Initial pool/menu omissions, older isolated active-skill fixtures encountering the newly enabled Greed prompt, reentrant-awakening test scheduling, one malformed fixture insertion, exact-versus-full skill button text, one unparented test Player cleanup, and mid-PLAY fixture receipt ledgers containing newly captured startup records were corrected without deleting assertions. Natural probes also corrected child-number/assigned-seat confusion, fee-control recognition, and inclusion of the real Duel Kill response in event accounting. Final acceptance requires one new source snapshot, all fifteen groups, the complete old CI matrix plus the new cases and all fifteen modes; earlier probes are not final acceptance.


## 2026-11-15 / QA-T353: Greed, Wrestle, PREP and field counters

`i05_sunny_counter_combinations.gd` adds 229 assertions to the existing mandatory external-loss suite (888 retained; now 1117). Actual Harvest draws feed AI Greed, David's committed Wrestle prevention, and Leo's replacement of the virtual counter Duel. Arbitrary/concrete fees, empty/good-field Nullification, immediate healing despite anti-Nullification, technical invalidation, normal source death and terminal FFA victory are covered. Paid resources and committed prevention do not roll back; events and physical entities complete/discard at most once.

Actual human Bridge field windows check seat authority, stale tokens and UI teardown. These local AI/human fixtures do not claim public Sunny ENet or LAN AI seat support. Native human input and the current AI turn actor are checked separately.

Strict diagnostic baseline `sunny-external-20261115-104425-74eba10b`: 1103 assertions / 40 failures. It reproduced the abandoned-counter parent-completion bug, alongside new-fixture mistakes (native input versus actor, deliberate refusal needed for the death case, and per-target root Nullification windows). Minimal production fix and fixture corrections: `104904-4559456a`, 1112/0. Added normal terminal victory: `105148-ad91620c`, 1117/0. Existing assertions, import/60-second suite deadlines and engine-error checks remain unchanged. Final same-source evidence is recorded under QA-T353.

2026-11-15 / I05c-5c AI：新增`i05_sunny_ai_cases.gd`143项挂既有组合必跑组，745+143=888。普通及真实烂忠厚赠PLAY中，默认AI拍片付1任意/具体牌、按公开缺血选两名合法其他对象，不生成USE；真实5经典/6奸雄开局中间谍随机合法非主公、限定一次、复原后新观察恢复资格，不按暗身份类别选人。值快照不含活对象/Callable，种子及公开状态相同、暗身份排列改变时选人相同；开关、模式、主体/目标复原、手牌/阶段/单位代次、目标死亡和空间快照过期均拒绝旧候选。实际AI贪污赢/输翻面/平局取1/放弃/技术失败/死亡/终局/阶段/重开，以及大卫保牌反击，仍沿共享批次与决斗入口。实际两山隔区、隐身/可见龙与满血第二目标、预大习内贤者摸4立即AI贪污且里奥自身奖励豁免、真实AI决斗致濒死贤者后新帧结束回合均验。

本机AI效果与真人彼得免效通过实际Bridge令牌验证，错座/旧令牌拒绝；此为本机AI与真人响应观察，不冒称多人LAN房间新增AI席位或自然公开Sunny ENet。普通AI展示等待保留0.6秒语义、测试用现有专用时钟；旧帧不收费，新帧重观察后再收费一次并结束阶段。

失败回执保留：000240-10668dc6为845/5且有注册器参数错误；新增夹具把reset误传roster、彼得写错名字、贪污策略桩误断言反击决斗选项。修正后000411-41b030f5为846/0。扩展山/龙/规则用例的000910-a21e68fe因把Player与String比较而编译失败并严格60秒超时；修正后001136-c21bab04虽RESULT864/0，仍因混合目标int/String比较报错判失败；同时修正生产候选重复判断的类型门后001355-069e0f8f为866/0。补真实贤者复原接续为001725-667819bb的871/0，再补死亡/终局/重开边界后002110-1f03b826导入及887/0、15.146秒。没有过滤引擎错误或降低旧745项/60秒标准。最终全量同源证据另记交接，三技能AI不等于完整I05c公开完成。

提交前修正隐私对照：原本交换2/3号位，两人都为反贼，不能用作不同身份类别的排列证据。改为2/4号位的反贼/内奸，并新增1项前置断言确认不同；同公开状态与随机种子的选人仍须相同。旧887/0及全量20261115-002323-51197933的28147/0与11项兼容保留为历史，不能作为修正后888项版本的最终同源凭据；须重新冻结全量及兼容验证。

2026-11-14 / I05c-5b：新增`i05_dragon_delayed_reveal_cases.gd`126项挂既有必跑组合组，619+126=745。注册火龙实际以任意/具体牌使用乐不思蜀、兵粮寸断、火烧连营，原实体进目标判定区，USE归单位而非控制者，仅向原目标显形。人类控制角色使用相同牌不使龙显形；其后明确麦克斯赠给桑尼PLAY的合法阶段前缀（不冒称完整自然烂忠厚调用），Sunny实际五谷只影响已向其显形且受伤的龙，额外牌先归龙、再被贪污，原判定牌仍保留而不提前判。房主/远端经实际“出牌→锦囊牌→延时锦囊→乐不思蜀”和目标令牌支付单位自己的手牌，错座/旧令牌拒绝、控制者不误付牌均验；控制者和非目标不会自动见到龙。不是自然召唤/公开桑尼ENet测试。

基线233914-7e1b14d2为739/18：六个龙延时实例均未显形，随后实际五谷/贪污也无法作用；另六项Bridge失败源于用例在CardSelector既有0.1秒tween确认信号发出前读取目标令牌。生产只补原事件的[target]，测试等待现有0.15秒（不改生产Tween/倒计时）后，234055-9f4cb260导入及745/0通过、5.564秒。新多出的6项是修正后真正触发的贪污回调断言，不是删除基线失败项；原619检查完整保留，无放宽门槛。无懈/舍己显形例外仍由既有全量组回归。

2026-11-14 / I05c-5a：新增`i05_strike_declaration_awakening_cases.gd`89项，由既有外部失牌必跑组加载，530+89=619；原14组与每组60秒门槛不变。实际普通杀/借刀要求的杀：大卫青龙摸1→桑尼贪污→大卫摔角→史蒂芬用最后无懈→完整觉醒选杀目标免疫→原杀仍命中。方天则第一目标大卫贤者摸4触发同链，第二目标史蒂芬仍受原杀。任意/具体原杀及无懈、实际费用/事件一次、后续新牌拒绝、原次数一次/借刀不占次数均验。神速用明确等待边界注入例验证，不冒称比尔同时拥有大卫技能。房主/远端Bridge以两名相邻目标和实际贤者/反击/无懈/免疫窗口验收，旧令牌拒绝、原控制者归还；此为资源阶段夹具，不冒称自然公开桑尼ENet。另验既有免疫在新声明付款前拒绝、底层未绑定直调拒绝，以及资格绑定不绕过藤甲/裸奔/布鲁斯下跪。

基线定向232304-cfa6b952复现普通/借刀四个实际命中断言失败；多目标夹具遗漏贤者确认，严格60秒超时。补显式贤者确认与生产资格绑定后232530-0b49c378为602/0。新增其他限制及Bridge后232658-0f5f8d0e严格超时：下跪反例错误地把状态设在史蒂芬身上，现行规则只识别布鲁斯，不能用非法夹具推翻生产检查。改为布鲁斯1体力空手的合法已下跪状态，并明确Bridge无人出桃；232857-28223482导入及619/0通过，4.554秒。全部旧断言保留，未跳过旧530项，失败回执完整保留。

2026-11-14 / I05c-4b上游5：新增独立必跑`test_i05_sunny_external_losses.gd`及`i05_sunny_external_loss_cases.gd`，本地run_headless及CI专项同样必跑，保留Sunny2357全部旧用例及每组60秒限制。普通拆/顺、已付换牌后的强制选牌、共享弃牌支付与真实校园霸主、寒冰剑不足两张/整两张、主公误杀忠臣清牌后，完整等待空手觉醒/精确新批次贪污/免疫后再恢复原父链。任意与具体原牌、贪污放弃/赢取/技术失效、不退牌不重付、不误弃新牌，房主/远端实际免疫窗口与输入归还均验。换牌用例明确为已付事件和强制选牌父链夹具，未冒称自然预习入口；Bridge未冒称自然公开桑尼ENet。后补真实摄魂刀已激活后伤害、两次拼点全输、支付最后4张手牌，先完整觉醒再翻面；贪污技术失效必须向已造成伤害的父链传播，无效旧帧不能完成原用牌。

定向首次225137-91d69400虽然RESULT269/0，但强制换牌夹具传入普通数组、违背函数Array[Player]参数，产生SCRIPT ERROR和资源遗留，严格判失败；改为显式强类型目标数组后225253-88e1e1a1为380/0。补校园霸主和整两张寒冰剑后225421-cfd508f4为483/4，校园霸主拼点桩误套到“主公同时是觉醒者”的惩罚用例，使原必赢贪污变平局；限定该桩仅校园霸主，保留全部验收断言，225548-f077f827为476/0、4.447秒。无生产规则更改、无过滤引擎错误或放宽门槛；完整回归和兼容以同源最终快照为准。

首次完整快照20261114-225654-220536a4：confirmed/card_transfer/i04_responses/i05_effects四组60秒严格超时，其余通过，Sunny2357及新组当时476均零失败。日志定位旧隔离夹具仅置awoken=true、遗漏awaken_effects_applied及awake_choice，新的支付屏障会正确等待真实免疫窗口。按这些用例“隔离觉醒”的原意补完整前置标志，保留每条原断言、原体力/伤害和全部旧数量；两共用reset另清effects_applied，避免跨例残留。真正末手牌触发和未完成觉醒等待由新专组正面验收，不给生产等待加测试旁路。该失败快照不得复用作验收，新增摄魂刀传播修复也必须由新快照覆盖。

后补摄魂刀54项，外部失牌专组总530项；定向sunny-external-20261114-230614-f61ab333导入及530/0通过，5.350秒。不得把早先476项结果当作这版530项的证据。

2026-11-11 / I05c-4b上游4（Q15/Q16）：新增`i05_sunny_rescue_awakening_cases.gd`247项，Sunny2357。真实酒杀进入求救，先桃回复后等待完整觉醒/贪污/免疫，再允许同人连续桃、下一位或原伤害结束。覆盖救他人、0体力自救、−1最后桃回0立即摸2、自救牌被贪污后仍死亡/由后续桑尼救回、平局拿1仍可用剩余牌、技术失效不回滚原治疗、任意及具体原资源。濒死批次许可只由觉醒奖励显式传入，普通批次的濒死拒绝及最终死亡拒绝仍保留。四组房主/远端使用自己回合决斗失败的合法前缀（布鲁斯已损1体力，响应杀后造成2伤），保证桑尼在普通求救顺序中尚未被询问；实际桃→0体力贪污/RPS→必选免疫→新牌自救或后续救援→原决斗完成。首次130721-a36f4ec2为2357/36，旧联机酒杀夹具未到预期求救窗口且桑尼已经被本轮询问，改为上述前缀后131117-1fce372c为2357/0、51.492秒；全部原断言和门槛保留。其余外部失牌及完整AI/公开整将仍待后续。

2026-11-11 / I05c-4b上游3：新增其他响应支付120项及Q13/Q14目标绑定64项，Sunny2110。无懈/舍己支付先记原事件、完整觉醒后继续反制/独立转移；舍己不让UI兜底抢在原事件前开启觉醒。AOE在声明时过滤已有觉醒目标禁令，保存整张牌名单，中途新免疫不再重筛；原决斗同样继续，之后新牌被免疫拒绝。原始南蛮/万箭与决斗、任意/具体原响应、贪污放弃/赢取、技术失效均验，房主/远端实际响应→免疫→无懈续链/舍己新伤害→原行动者归还。首次定向sunny-reaction-20261111-122309-d1aee175为2110/2，发现舍己空手扫描会遗留输入座位，补正常结束恢复输入、保留原断言后122557-75472bcb为2110/0。Q15求救时序已答先桃后觉醒/贪污，但本批尚未迁移求救；负体力自救后仍濒死的觉醒资格Q16单独待答。

2026-11-10 / I05c-4b上游第2项：新增`i05_sunny_other_use_payment_cases.gd`347项，Sunny1926。酒/桃、闪电/对人延时锦囊、空槽武器/防具/坐骑与三类替换的实际末手牌支付后，等待完整觉醒及贪污/免疫才完成原事件。酒桃原牌先入弃牌堆，再等觉醒后应用效果；判定牌、装备保留实际原实例。换装先完成可回滚的原子步骤再等待；辅助函数的两个生产父点及唯一旧测试调用均显式await，旧错误反馈不再误称已提交换装“未替换”。347项包括任意/已具体化原资源、贪污放弃/赢取/失效、旧装备只弃一次、六组房主/远端酒/延时/替换武器的实际必选免疫与旧令牌拒绝。定向sunny-reaction-20261110-205444-986c89c3为1926/0、44.213秒。Q13/Q14仍待答，未断言结算中途新免疫对原AOE/决斗的效力；其余响应和外部失牌仍待后续。

2026-11-10 / I05c-4b上游第1项：`i05_sunny_shared_payment_cases.gd`新增204项，Sunny1579。共用杀记录及即时锦囊支付后等待完整觉醒；实际普通杀/借刀杀/合法方天双目标杀/决斗的最后任意或具体牌，先觉醒摸2与贪污及免疫，再青龙摸1或原效果；技失效释放原事件不补伤害，不重付或重计。方天夹具持普通−1马保证两个目标均合法，不同时装备青龙。先184项定向（1559/0）通过后补四组房主/远端实际原杀/决斗免疫窗口、错座/旧令牌拒绝与行动者归还；首次全量20261110-203000-4b8e5f8a为1579/8，联机稻草人实际5体力却写死4，修为读取原体力、前不变后减1，全部204项保留，最终证据须覆盖修正。普通酒/桃/延时/装备、无懈/舍己及其余失牌入口仍按计划顺序另迁移。

2026-11-10 / I05c-4b-Q12响应入口：新增`i05_sunny_payment_awakening_cases.gd`98项，Sunny必跑组1375。最后一张任意/具体闪支付后，先完整觉醒（扣上限、摸2、实际贪污、必选免疫），再八卦摸1、最后完成原闪/原杀；放弃、赢取、平局取1、技术失效和重开均验。两个支付父点等待同一觉醒租约，公开旧能力关闭时也不跳过免疫；房主/远端Bridge实际必选窗口与错座/旧令牌拒绝。定向sunny-reaction-20261110-200318-bd19b8de为1375/0。首次全量20261110-200459-7b46733f的大卫反应组超时，旧装逼夹具仅置awoken=true、漏已结算标志/免疫选择，且仍用4上限；修为从基础3合法完成觉醒后的2/2及第三项免疫，原反击伤害断言按实际体力更新，保留全部728项及原意，不把窗口跳过当正确。此次仅迁移物理基本响应；普通使用、无懈/舍己及外部失牌的其余上游继续审计，不把本例通过当I05c整体完成。Q11验收后模块分组为Peter/David842及Sunny1277，所有旧模块各保留一次、总断言不变，详QA-T341。

2026-11-10 / I05c-4b2b-5b（Q11）：新增`i05_sunny_yudaxi_reward_exemption_cases.gd`18项，Sunny必跑组324。预大习成功奖励仍标EXTRA，单批corruption_exempt豁免在公布摸牌前写入；不触发或补发贪污，后续正常额外摸牌不继承豁免。同一实际规则中贤者4张仍立即贪污、里奥自己的X张单独豁免。同步奖励回调保留，补回调重开后的generation保护，旧规则不写新栈。定向sunny-reaction-20261110-193242-d4edf0b8为324/0。Q12已答先完整觉醒后八卦，下一真实支付上游等待仍在开发，不把规则回写当实现完成。

2026-11-10 / I05c-4b2b-5a：`i05_sunny_corruption_death_draw_cases.gd`新增86项挂Sunny必跑组，累计306。身份局反贼/奸雄最终死亡、身份公开、清牌后，击杀者奖励3张先贪污再返回死亡/原杀；任意/具体原杀、旧牌排除、赢/放弃/平局取1/失效、不重复奖励。实际大卫防止奖励被取、反击杀死桑尼，原两层死亡与用牌完整结束；乱斗无奖励、主公杀忠清牌不触发贪污/摔角保持。六人奸雄角色来自真实开局；房主/远端真实身份击杀进入奖励/RPS窗口。注册火龙的实际单位杀验证奖励归单位、潜行挡住桑尼，显形后才能贪污（单位/轮转前缀为明确夹具，不冒称自然召唤）。定向sunny-reaction-20261110-161543-d5c3d711为306/0，最终冻结源另把已存在的显形事件序号与新杀事件分开。Q11里奥成功奖励与Q12觉醒/装备同刻先后仍待裁决，当前不开放桑尼。

2026-11-10 / I05c-4b2b-4a：`i05_sunny_corruption_stage_draw_cases.gd`新增113项挂Sunny必跑组，累计220；已进入觉醒摸2后先贪污再选免疫，三处显式父链接失效结果，私有反应父调用等待同一已有觉醒租约而不重复扣上限/摸牌。实际偷药品取走末手牌，等觉醒及贪污后才下一目标；真实贤者复原摸4被取空→觉醒摸2又被取，仍只觉醒一次；麦克斯确认奖励先贪污再赠JUDGE/DRAW/PLAY，赠DRAW保持普通摸牌，房主/远端实际反应与后续必选免疫。初轮215/7源自嵌套夹具在已经空手时放五谷、以及赠判定目标没有判定牌，替换为合法贤者链并补判定牌后sunny-reaction-20261110-155348-c24e6e09为220/0。史蒂芬统一按手册基础3上限；Q12原提问4/4已纠正，触发先后仍待裁决，不把当前UI时序当采用规则。Q11里奥成功奖励亦待答，整I05c未完成。

2026-11-10 / I05c-4b2b-3：新增必跑`test_i05_sunny_reactions.gd`，当前107断言（`i05_sunny_corruption_response_draw_cases.gd`），本地runner现在导入＋13组＝14回执，CI既有spec循环新增同名入口；旧12组及其60秒门槛、全部旧模块保持原样，无移动/删减旧测试。验证八卦任意/具体闪先真实支付、奖励被贪污后原闪仍有效，凯文受伤/伤人逐点奖励先贪污再下一点、平局不重猜；技术失效不回滚已造成伤害，大卫反击杀死原来源/反击经预习改卸甲移除八卦，房主及远端真实响应/RPS续接。定向初轮625/2是出拳前失效却误计贪污出拳；修正期引入缩进错误导致两轮加载失败超时，纠正后独立新组sunny-reaction-20261110-152917-b9858c13为107/0。入口静态预载本模块，不把脚本加载错误遗留到中途。原时限和过滤检查未改；更早effect组1795继续原样运行。Q11仅阻塞未来里奥规则奖励，详QA。

2026-11-10 / I05c-4b2b-2：`i05_sunny_corruption_strike_draw_cases.gd`新增129项，效果组1795、摸牌定向521。迁移青龙及五个杀记录父点，覆盖普通/火/雷杀、任意/具体支付、酒冻结、赢/放弃/技术失效、真实南蛮响应杀、两次原版借刀同回合仅首杀奖励及不占主动次数、已授权神速杀子流、方天无青龙的正常多目标路径，房主/远端真实借刀及奖励出拳输入。未编造方天与青龙同时装备。首轮521/4为Bridge夹具漏答贪污后合法舍己窗口，补明确放弃策略后521/0；时限/原断言不改。八卦/凯文及其余父链尚未迁移，桑尼仍未公开。最终全量证据以QA/交接为准。

I05c-4b2b-1补充：实际摔角反击被里奥改为卸甲，移除已经触发奖励的雌雄武器，原杀仍须续接伤害。新增8项令本批共196项、效果组1666、定向392。定向392/2确认原提交后武器校验错误，修复为发动前照常校验、摸牌已提交后只复查生命周期/阶段，392/0通过；下方188/384和早期完整快照只是补充前记录，最终证据必须覆盖修复后的冻结源，不复用旧全量绿灯。

2026-11-10 / I05c-4b2b-1：`i05_sunny_corruption_card_draw_cases.gd`新增188项挂既有必跑效果组（1470＋188＝1658）；摸牌定向累计384项。真实支付五谷/卸甲后逐批先入手、待贪污后下一目标；赢/放弃/平局拿1、复原过期/终局不处理下一目标；雌雄无牌及选让摸牌两分支，任意/已具体化原杀均先处理奖励贪污再闪/伤害，保留旧具体手牌；真实大卫防止后反击杀死五谷使用者，原五谷仍处理下一目标并完成一次。房主/远端Bridge覆盖实际已支付五谷/卸甲进入贪污、双方出拳与错座/旧令牌拒绝；这是状态夹具，不等同公开桑尼自然ENet。首轮测试夹具错误使用CROSSBOW/RENWANG_SHIELD枚举导致加载失败和超时，修正为现有LIANNU/RENWANG_DUN后384/0通过；未改时限或过滤标准。此批只迁移入口表第1行，其余额外摸牌父链与整将公开仍待后续，详最新QA/交接。

2026-11-10 / I05c-4b2a：最新Q10覆盖贤者摸牌的旧Q9/Q9b延后策略。`i05_sunny_corruption_sage_cases.gd`新增84项挂既有必跑效果组（1386＋84＝1470）；定向摸牌入口累计196项。验证即时贪污首次放弃、赢取4/输翻面、平局拿1/超时拿1/重拼、原批次不可重开、大卫真实摔角与反击、复原过期、私有门控，以及实际预大习内贤者摸4先完成贪污再处理后续救援，结束不补发。房主/远端Bridge真实确认、取消、双方出拳、错座及旧令牌均验；Bridge为明确状态夹具，不是自然公开桑尼ENet。已有直接贤者测试调用改为显式await，不删旧断言。其余额外摸牌父链仍未迁移，桑尼未开放；全量验证证据见最新QA/交接。Q10旧零剩余题已撤回，不再待答，下方延后条目为历史。

2026-11-10 / I05c-4b1：`i05_deferred_draw_resource_cases.gd`挂原必跑效果组，新增58项，原1328保留、效果组现1386。验证合法支付/移牌/补牌后的原批次剩余身份、交错批次、不偷后来牌、静默信号契约、同数量null替换时旧失牌事务拒绝，以及真实预大习→贤者→各用两桃救1/2人的剩余资源。`test_i05_draw_receipts.gd`是可选定向入口（旧54＋新58＝112），不在正式效果组中重复运行，也不能替代完整回归/联机门禁。Player手牌增删必须走append_hand_card_silent/take_hand_card_at/clear_hand_silent或现有包装；裸数组接口仅供纯数组调用者，不能绕过追踪。物理资源有效性不等于贪污发动资格；Q9b已答延后取尚存原牌，零剩余是否仍拼点的Q10待答。实际贪污与整将公开未完成，详最新QA/交接。

2026-11-09 / I05c-4a：`i05_extra_draw_batch_cases.gd`挂既有必跑效果组，新增54项、原1274保留，现1328。仅验证同步摸牌批次的资源/生命周期与语义记录：原新牌索引、旧具体手牌不动、零摸牌、重开/终局/复原/追加后不盲取、真实初始化、麦克斯赠DRAW及本人奖励、比尔/好田阶段加摸、他人DRAW中觉醒、真实预大习内部贤者来源标记。`_extra_draw_receipts_enabled`默认false；本批不实现贪污询问、拼点、取得或延后调度。Q9已定预大习期间不插入，Q9b结算后是否补发待答；严格快照校验失败只是资源安全检查，不是允许取消已发动效果的玩法规则，后续须处理合法中途变化。下方3b为历史批次，最新状态/证据见QA和交接。

2026-11-09 / I05c-3b：实际间谍回归`i05_sunny_spy_cases.gd`挂原必跑效果组，新增151项，原1123保留、效果组现1274。Q7专门禁止彼得免除间谍交换；Q8首次贪污询问基础读条耗尽不发动，两题已答。覆盖无手牌费用、主公发动者交换其他两人、非主公自己参与、同身份配对、限定次数及贤者复原、6/8/10奸雄缓存、真实获赠PLAY、原生按钮及房主/远端Bridge取消/过期/身份保密。Bridge识别实际随机主公座位，不固定0号位；这是私有资源/阶段夹具，整将自然ENet仍留公开门禁。当前完成状态及证据以最新QA/交接为准，下方3a待答为历史。

2026-11-09 / I05c-3a：`i05_sunny_identity_state_cases.gd`继续挂必跑效果组，新增99项身份原语/奸雄缓存/限定次数复原回归，效果组现1123，原1024保留。此为底层组件，未实现【间谍】选人、免效、限定技提交及其联机入口；Q7彼得免效/次数、Q8贪污初次询问超时仍待答。不以纯组件或观察值测试冒称完整技能/自然ENet通过。后续执行顺序与实测证据见QA及当前交接。

2026-11-09 / I05c-2：`i05_sunny_filming_cases.gd`由必跑的`test_i05_effects.gd`加载，新增182项拍片私有实现回归，原842项效果断言保留。覆盖原任意/具体手牌费用、两个其他角色与满血、重复发动、彼得免效、山分区/火龙潜行、真实麦克斯获赠PLAY、原生详情/头像/弃牌、房主与远端Bridge确认/取消/超时回调/复原及错座旧令牌，以及费用待答期间终局不扣牌。Bridge使用明确资源夹具，超时分支调用既有答复回调，不冒称自然读条耗尽或新将完整自然ENet。桑尼仍metadata_only，私有开关默认false。正式主回归入口`Test/run_headless.ps1`仍应产生导入加12组共13份回执；I05效果1024、反击728、公开入口16均必跑，不能只运行本模块代替旧门禁。最新实际验证证据以QA/交接为准，下方F03“当前”描述为历史。

当前F03c / QA-T186完成：七组16522（6565/9689/54/103/24/51/36）全绿，证据`20261007-143022-56abb383`，导入7.047秒、核心42.855秒、已确认53.780秒，其余不足1秒，退出/错误/超时均合格。F03a/b/c累计225新增，里奥已进入prototype、自选菜单和随机池；下方旧metadata_only/未完成只为历史。

分组映射：basic_prompt_cases、nullification_prompt_cases、bloodthirsty_rps_cases三个完整旧模块（708项）由已确认组移到核心，原模块未改、各只加载一次。前后七组总断言守恒，不能按单组断言下降误判为漏跑。已确认日志采用核心组相同分批方式，每条PASS/FAIL保留、失败即时输出、结尾flush；不降低60秒门槛。141604旧metadata告警失败及142238/142626零断言失败但超时均保留，最后完整重验才算通过。F03-Q1真实下跪、实际菜单选择/可达/技能详情及非本人AI放弃均在核心新模块运行，人工视觉未验。

F03b：`leo_mode_cases.gd`挂核心组，从真实2/3人乱斗及5人经典开局到三技能及终局各重复两次；参数化已有`full_game_cases`另跑六场默认行动里奥局，原D04默认稻草人不变。QA-T185新增129，七组16493（5830/10395/54/103/24/51/36）全绿，证据`20261007-140701-a8677df1`。比尔基础3仍验；主公初始化独立+1后比尔真实主公上限4。里奥菜单仍待F03c，不冒充人工视觉。

F03a：`leo_lifecycle_cases.gd`挂核心组，67项真实决斗/替换、普通求救、成功保三个区、贤者真实窗口及单里奥子救援。QA-T184七组16364（5702/10395/53/103/24/51/36）全通过，日志`20261007-135718-122663b1`。其夹具单独清判定区/坐骑缓存和旧自救override，不改生产规则、不删旧断言。里奥仍metadata_only，F03b模式组合及F03-Q1待答/F03c开放另验。

`prep_integration_cases.gd`挂已确认组，`prep_damage_observer.gd`仅只读观察真实调度后的DamageRecord：QA-T183新增96，七组16297（5635/10395/53/103/24/51/36）全绿，证据`20261007-124052-933cd57e`。真实PREP→借刀强制第二目标及旧答复隔离、NULL批量标记/父牌完成、方天荆棘真实死亡后的无源伤害、真实获赠PLAY和舍己响应组合已验。F02当前生产范围完成，下一F03；下方旧未完成说明仅历史。首轮范围外追加目标夹具失败和两次受限根证书导入失败均保留，最终放开环境限制重验；没有过滤错误、删断言或改120/60秒。已确认组56.937秒接近60秒，后续加F03测试前须关注合法分组，不能抬高门槛或漏跑旧用例。

`prep_borrowed_replace_cases.gd`挂已确认组；QA-T182新增393，七组16201全绿，证据`20261007-122817-d7c82494`。双向/连续/虚拟/两人/额度/失效及真实暗置武器取走声明、换成借刀后Q20死亡续接已验。首轮类型夹具失败保留，不删断言或改120/60秒；预习借刀已接，F02组合收口及人工视觉尚未完成。

`borrowed_original_entry_cases.gd`挂已确认组，QA-T181：原版菜单/共同玩家及AI入口、远距离第一目标、具体原对象支付、两次限额/实际操作者、确认取消/过期及无合法目标均验；Q20死亡模块增加原版入口真实奇偶无懈链。新增197、七组15808（5635/9906/53/103/24/51/36），证据`20261007-105915-5d463dac`，无失败/错误/超时，120/60秒不变。下方QA-T180等未公开菜单的说明仅当时历史状态；预习进出借刀及人工视觉仍未验。

`borrowed_extra_targets_cases.gd`挂已确认组：Q19/Q21真实方天追加窗口及已支付借刀调用链；新增129/七组15611全绿，QA-T180，证据`20261007-100006-0177748a`。正常超时提交当前勾选目标，固定目标保留；技术关闭/过期不交武器不支付杀。任意/具体、酒火杀两目标、原武器转移及选择失效、四合法目标且非最后手牌边界已验。没有原版牌菜单/预习借刀或人工视觉验收；120/60秒不变。

`borrowed_death_nullification_cases.gd`挂已确认组，验Q20真实五人身份局的借刀支付、虚拟无懈费用最终死亡、奇偶链、出杀/拒绝/无牌及技术失效；新增86/七组15482全绿，QA-T179，证据`20261007-092506-84d62783`。两次夹具实例字段误用导致解析失败及超时，修正并保留日志，不放宽120/60秒。方天选择及整个借刀菜单/预习入口仍未完成。

`borrowed_multi_effect_cases.gd`挂已确认组，仅验借刀杀已确认目标集合的多目标效果层；新增140/七组15396全绿，QA-T178，证据`20261007-091651-be3c9eb8`。原普通借刀回归保留；不能把效果层当方天选择窗口、死亡无懈或完整牌菜单完成。两轮夹具失败日志保留，不放宽120/60秒。

`borrowed_paid_effect_cases.gd`由已确认组运行，普通已支付借刀及真实出杀选择窗口范围验收：新增240、七组15256全绿，QA-T177，证据`.git/local-ci/20261006-231530-f57de843/`。真实任意/具体原牌、闪/无懈事实与完成顺序、原武器交手牌、青釭剑普通主动杀额度已满时仍可响应借刀；不把这些当方天/致死虚拟无懈/暗置复杂交武器/菜单和预习入口已完成。首轮夹具六失败日志230855保留。

`borrowed_second_target_cases.gd`验借刀第二目标的真实强制读条窗口及AI，同名原武器/人物/范围过期、旧答复/超时隔离。新增71、七组15016全绿，QA-T176；仅选择入口，不把它当借刀完整结算已接。

`borrowed_sword_foundation_cases.gd`验追加枚举及最新Q16借刀牌两次计数；Q18要求的杀不占普通额度，真实杀入口下一批接。新增30、七组14945通过，QA-T175；不采用旧第一目标独立额度草稿，旧已提交断言保留。

`prep_group_scope_cases.gd`验正式声明范围、虚拟群体转换、真实无懈和技术失效。新90、七组14915全绿（QA-T174）；动态恢复/死亡夹具仅验证快照不扩展或缩小，不创造复活/同时行动玩法。

`prep_group_replace_cases.gd`由已确认组挂载，验五种群体转换与两人南蛮/万箭例外、两目标铁索扩大、Q14空条件目标、连续/限额/真实窗口。新841，七组14825；旧断言与固定120/60秒门槛保留，QA-T173。声明范围正式快照、虚拟/其他复杂组合与借刀仍按下一子任务验证。

`prep_steal_replace_cases.gd`由已确认规则组挂载，验固定单体→拆顺及PREP-12真实强制选牌。原候选精确断言增加合法拆顺、不删除旧限制；每组仍60秒，七组总13914=13494+420。

F02b-2b-2a新增`prep_paid_steal_cases.gd`在已确认规则组运行：先真实支付原决斗，再直接调用已支付拆/顺效果入口，验证不二次付牌/发布事实、只计最终类别、同一目标原牌移动、原实体名称不变及技术失效隔离。它不是更换候选/强制选牌窗口的完整验收；新窗口留下一子项。原拆/顺全路径仍由既有模块回归。

F02b-2b-1补充分组：连续两次核心超时后，将choice_prompt至soul_blade_activation的29个完整E03响应/装备生命周期模块整体移至已确认规则组；原模块未删改，新增宿主strike辅助与核心原实现一致。每组仍60秒，须核对七组总断言等于全部旧断言加新增，不能把同一用例漏跑/重复跑当通过。映射直接见两个宿主的模块加载清单。

2026-10-06测试分组：预习完成事实的七个独立模块（基本牌、主动杀、装备、群体锦囊、单体/铁索、无懈整链、舍己/虚拟神速）及新增固定目标替换模块在`test_confirmed_rules.gd`执行。原模块与断言全部保留；核心组仍跑其余原用例，七组名称与每组60秒门槛不变。两个宿主使用相同reset_players夹具，新增替换模块额外清坐骑缓存以隔离其距离用例。此调整不是跳过用例，也不按整批总时间掩盖单组超时。

使用与 CI 一致的 Godot 4.7.2，在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Test/run_headless.ps1 -GodotPath 'C:\path\Godot_v4.7.2-stable_win64.exe'
```

脚本不下载引擎、不启动交互游戏、不提交或推送。它将当前工作区的
`Scripts/Scenes/Test/project.godot`（含未提交和未跟踪的非忽略文件）复制到
Git 元数据目录的 `local-ci/<唯一运行号>/project`；保留源文件哈希、基线提交、
工作区状态、引擎哈希、导入和七组测试各自的标准输出、标准错误及 `results.json`。
不复制 `.godot` 缓存、PDF 或个人文档；未来增加其他资源目录时须同步扩充复制清单。
源项目存在 `override.cfg` 时拒绝运行，避免静默忽略已有自定义配置。

只有隔离副本使用 `headless_override.cfg`：关闭 stdout 的逐条强制刷新，正常退出
仍保存全部输出，stderr 始终刷新。Godot 官方说明该调试版默认设置可能影响大量
输出时的性能，见 [ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-application-run-flush-stdout-on-print)。
被强制终止时 stdout 尾部可能未刷新，因此超时始终判失败，即使已经出现成功 RESULT。
不改正式 `project.godot`、生产逻辑或 Linux CI。

2026-10-06本地验证补充：引擎使用官方命令行 `--disable-render-loop`，只关闭
无窗口绘制循环，保留场景树、GUI节点、选择信号、process_frame和真实计时。
不使用 `--fixed-fps` 或时间缩放，不跳过断言，也不将本地结果视作人工视觉验收。
manifest记录此开关。此前通过的原隔离快照在同机重验也于60.483秒超时；
仅关闭绘制后的当前代码诊断七组12781通过，核心52.807秒。
原120/60秒门槛、错误检查和全部历史日志仍保留，每批须用正式脚本重新验证。

Windows 本地捕获通过 `ProcessStartInfo` 启动无窗口进程，并行将 stdout/stderr
原字节流异步复制到缓冲日志文件，退出后等待两条流写完，再检查退出码与日志。
不经过 PowerShell 逐行管道，也不直接将引擎输出句柄指向磁盘文件。
[WindowsTerminalLogger 源码](https://github.com/godotengine/godot/blob/master/platform/windows/windows_terminal_logger.cpp)
显示调试输出逐条调用 `FlushFileBuffers`；仅关闭上面的普通 stdout 刷新设置仍不足以
避免直接文件句柄的磁盘刷新成本。2026-10-04 同机诊断中，200次独立print从约1.4秒
降至约1.9毫秒，标签更新约9毫秒；完整七组核心从超时恢复为19.240秒、3399断言通过。
日志内容、七组、错误规则和120/60秒限制保持，退出及流写完的耗时均计入原限额。
历史超时日志保留；此测量不承诺任意主机的固定耗时。

验收门槛不变：导入 120 秒，每组 60 秒；退出码为 0、每组唯一且正断言数的
`RESULT: N asserts, 0 failures`、无脚本错误/ERROR/Parse Error/FAIL、没有超时。
导入失败不启动测试；某组失败仍记录后续各组，整体退出 1。脚本保留所有隔离副本
和日志，不自动删除历史证据。使用含 `%` 或双引号的引擎/仓库路径会明确拒绝。
