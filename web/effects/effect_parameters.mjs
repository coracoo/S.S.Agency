// 共同参数契约v1。单位为秒、父容器像素；真实命中事件单独传入hitAge。
export function sample(clock, hand, target, elapsed, launch, impactAt, hitAge = -1, flightOrigin = null) {
  let phase = 0, charge = 0, bolt = [...hand], flash = 0;
  if (hitAge >= 0) { phase = 3; flash = Math.exp(-hitAge * 13); }
  else if (elapsed < launch) { phase = 1; charge = Math.max(0, Math.min(1, elapsed / launch)); }
  else if (elapsed < impactAt) {
    phase = 2;
    if (flightOrigin) hand = [...flightOrigin];
    const u = Math.max(0, Math.min(1, (elapsed - launch) / (impactAt - launch)));
    bolt = hand.map((v, i) => v + (target[i] - v) * u);
  }
  return {time: clock, hand: [...hand], target: [...target], bolt, charge, phase, impact: Math.max(hitAge, 0), flash};
}
