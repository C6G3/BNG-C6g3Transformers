-- Speaker Transformer — vehicle editor live extension for BeamNG.drive.
-- Repository: https://github.com/C6G3/BNG-C6g3Transformers
-- Forked from Prop Trigger Transformer (vePropTriggerTransformer.lua) and Trigger Transformer (veTriggerTransformer.lua).
-- Supports dual rotation modes:
--   1. Prop-Attached Speakers (targetProp defined): Position-fixing rotation math around prop global center.
--   2. Standard 3-Node Speakers (idx/idy/idRef/idX/idY without targetProp): Standard TriggerTransformer rotation math.

local M = {}

local im = ui_imgui

local wndName = "Speaker Transformer"
local mainWndFlags = bit.bor(im.WindowFlags_NoBringToFrontOnFocus)
M.menuEntry = "Speaker Transformer"

local windowOpen = im.BoolPtr(false)

local nodeRenderRadius = 0.02
local nodeHoveredRenderRadius = 0.03
local nodeCollisionRadius = 0.035
local maxTriggerDistance = 1000

local scaleGizmoSpeed = 2.25

-- Set to false so the gizmo matches the c6g3SoundSystem's 1:1 meter coordinate scale.
local useRawNodeDistanceScaling = false

local function amplifyAxisGizmoScale(scl, speed)
  local k = speed or 1
  return vec3(1 + (scl.x - 1) * k, 1 + (scl.y - 1) * k, 1 + (scl.z - 1) * k)
end

local zeroVec = vec3(0, 0, 0)
local regularColor = ColorF(0.75, 1, 0, 1)
local hoveredColor = ColorF(1, 0.65, 0, 1)
local selectedColor = ColorF(1, 0.65, 0, 0.25)
local blankColor = ColorF(0, 0, 0, 0)
local redColor = ColorF(1, 0, 0, 0.25)
local greenColor = ColorF(0, 1, 0, 0.25)
local whiteColor = ColorF(1, 1, 1, 0.25)
local lineRedColor = ColorF(1, 0, 0, 1)
local lineGreenColor = ColorF(0, 1, 0, 1)
local lineBlueColor = ColorF(0, 0, 1, 1)
local textRedColor = ColorF(1, 0, 0, 1)
local textWhiteColor = ColorF(1, 1, 1, 1)
local textBackgroundColor = ColorI(0, 0, 0, 192)

local function mod360Deg(deg)
  deg = deg % 360
  if deg < 0 then deg = deg + 360 end
  return deg
end

local function modRotationRad(r)
  return mod360Deg(r * 180 / math.pi) * math.pi / 180
end

local function modRotationVec3(v)
  return vec3(modRotationRad(v.x), modRotationRad(v.y), modRotationRad(v.z))
end

local RAD_TO_DEG = 180 / math.pi
local DEG_TO_RAD = math.pi / 180

local function vec3RadToDeg(v)
  return vec3(v.x * RAD_TO_DEG, v.y * RAD_TO_DEG, v.z * RAD_TO_DEG)
end

local function col(row, name, defaultIdx)
  if type(row) ~= 'table' then return nil end
  for k, v in pairs(row) do
    if type(k) == 'string' and k:lower() == name:lower() then return v end
  end
  if defaultIdx then return row[defaultIdx] end
  return nil
end

local function spkId(spk)
  return col(spk, "name", 1) or col(spk, "id", 1) or "speaker"
end

local function isSpeaker(spk)
  return type(spk) == 'table' and spkId(spk) ~= nil
end

local function spkPosSource(spk)
  return (type(spk.position) == 'table') and spk.position or spk
end

local function spkTargetProp(spk)
  local pos = spkPosSource(spk)
  local tProp = col(pos, "targetProp", 9) or spk.targetProp
  if tProp and tProp ~= "" then return tProp end
  return nil
end

local function isPropAttachedSpeaker(spk)
  return spkTargetProp(spk) ~= nil
end

local function spkIdRef(spk)
  local pos = spkPosSource(spk)
  return col(pos, "idRef", 1) or col(pos, "idref", 1) or spk.idRef or spk.node
end

local function spkIdX(spk)
  local pos = spkPosSource(spk)
  return col(pos, "idX", 2) or col(pos, "idx", 2) or spk.idX or spk.idx
end

local function spkIdY(spk)
  local pos = spkPosSource(spk)
  return col(pos, "idY", 3) or col(pos, "idy", 3) or spk.idY or spk.idy
end

local function spkBaseTrans(spk)
  local pos = spkPosSource(spk)
  local val = col(pos, "baseTranslation", 8) or col(pos, "translation", 7) or spk.baseTranslation or spk.translation
  if not val then return vec3(0, 0, 0) end
  if type(val) == 'table' then
    return vec3(tonumber(val.x or val[1]) or 0, tonumber(val.y or val[2]) or 0, tonumber(val.z or val[3]) or 0)
  elseif type(val) == 'cdata' then
    return vec3(val)
  end
  return vec3(0, 0, 0)
end

local function spkBaseRot(spk)
  local pos = spkPosSource(spk)
  local val = col(pos, "baseRotation", 5) or col(pos, "rotation", 6) or spk.baseRotation or spk.rotation
  if not val then return vec3(0, 0, 0) end
  if type(val) == 'table' then
    return vec3(tonumber(val.x or val[1]) or 0, tonumber(val.y or val[2]) or 0, tonumber(val.z or val[3]) or 0)
  elseif type(val) == 'cdata' then
    return vec3(val.x or 0, val.y or 0, val.z or 0)
  end
  return vec3(0, 0, 0)
end

local function spkSize(spk)
  local pos = spkPosSource(spk)
  local val = col(pos, "radius", 4) or col(pos, "size", 4) or spk.radius or spk.size
  if type(val) == 'number' then return val end
  if type(val) == 'table' then return tonumber(val.x or val[1]) or 0.1 end
  if type(val) == 'cdata' then return val.x or 0.1 end
  return 0.1
end

local function eulerToMatrix(v)
  local x = v.x or v[1] or 0
  local y = v.y or v[2] or 0
  local z = v.z or v[3] or 0
  x, y, z = math.rad(x), math.rad(y), math.rad(z)
  local rotX = MatrixF(true)
  local rotY = MatrixF(true)
  local rotZ = MatrixF(true)
  rotX:setFromEuler(vec3(x, 0, 0))
  rotY:setFromEuler(vec3(0, y, 0))
  rotZ:setFromEuler(vec3(0, 0, z))
  local m = rotX:copy()
  m:mul(rotY)
  m:mul(rotZ)
  return m
end

local function eulerFromMatrixXYZ(m)
    local sy = -m:getColumn(2).x
    local cy = math.sqrt(1 - sy*sy)
    
    local x, y, z
    if cy > 1e-6 then
        x = math.atan2(m:getColumn(2).y, m:getColumn(2).z)
        y = math.atan2(sy, cy)
        z = math.atan2(m:getColumn(1).x, m:getColumn(0).x)
    else
        x = math.atan2(m:getColumn(0).y, m:getColumn(1).y)
        y = math.pi / 2 * (sy > 0 and 1 or -1)
        z = 0
    end
    return vec3(x, y, z)
end

local initStateTemplate = {
  mode = 1,
  propertyEditing = nil,
  speakersData = nil,
  hitSpeakerRefNodes = {},
  speakerSelectorIdx = 1,
  speakerSelectorCount = 1,
  pickedSpeaker = nil,
  hoveredSpeaker = nil,
  lastBaseTranslation = vec3(),
  lastBaseRotationEuler = vec3(),
  lastSize = vec3(),
  axisGizmo = {
    startPos = vec3(),
    startRot = quat(),
  },
}

-- Persistent state table for our dynamic sliders across UI refreshes
local dynLimits = {
  gain = { min = -100, max = 30 },
  outerGain = { min = -100, max = 30 },
  peakGain = { min = -50, max = 30 },
  distThresholddB = { min = -60, max = 10 },
  distFactor = { min = 0, max = 50 }
}

local initStates = {}
local states = {}
local initVehDatas = {}

local initVehData = nil
local state = nil

local inputBaseTranslation = im.ArrayFloat(3)
local inputBaseRotationDeg = im.ArrayFloat(3)
local inputSizeSphere = im.FloatPtr(1)

local function step3(v)
  return { im.FloatPtr(v), im.FloatPtr(v), im.FloatPtr(v) }
end

local stepBaseTranslation = step3(0.01)
local stepBaseRotationDeg = step3(1.0)
local stepSizeSphere = im.FloatPtr(0.01)

local dragging = false
local gizmoDirty = false
local showRefAxis = true

local beamngVehicleClass = "BeamNGVehicle"
local vehicleSelectableLock = false
local savedVehicleSelectable = true

local function updateBeamngVehicleSelectableLock()
  if not editor or not editor.getObjectTypeSelectable or not editor.setObjectTypeSelectable then return end
  local wantLock = windowOpen[0] and vEditor and vEditor.vehicle
  if wantLock then
    if not vehicleSelectableLock then
      savedVehicleSelectable = editor.getObjectTypeSelectable(beamngVehicleClass)
      editor.setObjectTypeSelectable(beamngVehicleClass, false)
      editor.clearObjectSelection()
      vehicleSelectableLock = true
    end
  elseif vehicleSelectableLock then
    editor.setObjectTypeSelectable(beamngVehicleClass, savedVehicleSelectable)
    vehicleSelectableLock = false
  end
end

local function getNodeId(nodeStr)
  if type(nodeStr) == 'number' then return nodeStr end
  local nodes = vEditor.vdata and vEditor.vdata.nodes
  if not nodeStr or type(nodes) ~= 'table' then return 0 end
  local n = nodes[nodeStr]
  if n and n.cid then return n.cid end
  for _, node in pairs(nodes) do
    if node.id == nodeStr or node.name == nodeStr then return node.cid or 0 end
  end
  return 0
end

local function getTargetPropId(spk)
  local tProp = spkTargetProp(spk)
  if not tProp or tProp == "" then return nil end
  local props = vEditor.vdata and vEditor.vdata.props
  if not props then return nil end
  for _, prop in pairs(props) do
    if prop.mesh == tProp then return prop.pid end
  end
  return nil
end

local function getSpeakerFrame(spk)
  local beObj = vEditor.vehicle
  if not beObj then return nil end
  local stObj = scenetree.findObject(beObj:getID())
  if not stObj then return nil end

  local tProp = spkTargetProp(spk)
  if tProp and tProp ~= "" then
    local pid = getTargetPropId(spk)
    if not pid then return nil end
    local propObj = beObj:getProp(pid)
    if not propObj then return nil end
    local worldMat = propObj:getLiveTransformWorld()

    local currentRefPos = stObj:getPosition()
    local baseCenter = worldMat:getColumn(3) + vec3(currentRefPos)

    local mat = MatrixF(true)
    mat:setColumn(0, worldMat:getColumn(0))
    mat:setColumn(1, worldMat:getColumn(1))
    mat:setColumn(2, worldMat:getColumn(2))
    mat:setPosition(baseCenter)
    return mat, 1, 1
  end

  local idRef = getNodeId(spkIdRef(spk))
  local idX   = getNodeId(spkIdX(spk))
  local idY   = getNodeId(spkIdY(spk))

  local rawRefPhys = beObj:getNodePosition(beObj:getRefNodeId())
  if not rawRefPhys then return nil end
  local pRefNodePhys = vec3(rawRefPhys)

  local rawPRef = beObj:getNodePosition(idRef)
  if not rawPRef then return nil end
  local pRef = vec3(rawPRef)

  local refMat = stObj:getRefNodeMatrix()
  if not refMat then return nil end

  local offsetFromRef = pRef - pRefNodePhys
  local pRefWorld = vec3(refMat:getPosition()) + offsetFromRef

  local mat = MatrixF(true)
  if idX == 0 or idY == 0 then
    mat:setPosition(pRefWorld)
    return mat, 1, 1
  else
    local rawPX = beObj:getNodePosition(idX)
    local rawPY = beObj:getNodePosition(idY)
    if not rawPX or not rawPY then return nil end
    local pX = vec3(rawPX)
    local pY = vec3(rawPY)

    local vecX = pX - pRef
    local vecY = pY - pRef
    local rawLenX = vecX:length()
    local rawLenY = vecY:length()
    if not rawLenX or rawLenX < 0.0001 then rawLenX = 1 end
    if not rawLenY or rawLenY < 0.0001 then rawLenY = 1 end

    local dirX = vecX:normalized()
    local dirY = vecY:normalized()

    local dirZ = dirX:cross(dirY):normalized()
    dirY = dirZ:cross(dirX):normalized()

    if dirX:squaredLength() < 0.0001 then dirX = vec3(1, 0, 0) end
    if dirY:squaredLength() < 0.0001 then dirY = vec3(0, 1, 0) end
    if dirZ:squaredLength() < 0.0001 then dirZ = vec3(0, 0, 1) end

    mat:setColumn(0, dirX)
    mat:setColumn(1, dirY)
    mat:setColumn(2, dirZ)
    mat:setPosition(pRefWorld)
    return mat, rawLenX, rawLenY
  end
end

local function getSpeakerGlobalCenter(spk)
  local frameMat, rawLenX, rawLenY = getSpeakerFrame(spk)
  if not frameMat then return nil end
  rawLenX = rawLenX or 1
  rawLenY = rawLenY or 1
  if not useRawNodeDistanceScaling then
    rawLenX, rawLenY = 1, 1
  end

  local bRot = spkBaseRot(spk)
  local brMat = eulerToMatrix(bRot)

  local workMat = MatrixF(true)
  workMat:setColumn(0, frameMat:getColumn(0))
  workMat:setColumn(1, frameMat:getColumn(1))
  workMat:setColumn(2, frameMat:getColumn(2))
  workMat:mul(brMat)

  local bT = spkBaseTrans(spk)
  local bTx = bT and (bT.x or bT[1]) or 0
  local bTy = bT and (bT.y or bT[2]) or 0
  local bTz = bT and (bT.z or bT[3]) or 0

  local worldTrans = workMat:getColumn(0) * (bTx * rawLenX)
                   + workMat:getColumn(1) * (bTy * rawLenY)
                   + workMat:getColumn(2) * bTz

  local centerPos = frameMat:getPosition() + worldTrans
  local radius = spkSize(spk)
  if radius and radius > 0 then
    centerPos = centerPos + workMat:getColumn(1) * radius
  end
  workMat:setPosition(centerPos)
  return workMat:getPosition(), workMat, frameMat, rawLenX, rawLenY
end

local function syncSpeakerToEditorVdata(spk)
  if not vEditor.vdata then return end
  local spkList = vEditor.vdata.c6g3SoundSystem_Speakers or vEditor.vdata.speakers
  if not spkList or type(spkList) ~= 'table' then return end
  local id = spkId(spk)
  if not id then return end

  for _, origSpk in pairs(spkList) do
    if type(origSpk) == 'table' and spkId(origSpk) == id then
      local bT = spkBaseTrans(spk)
      local bR = spkBaseRot(spk)
      local sz = spkSize(spk)

      local function updateOrig(t)
        if not t or type(t) ~= 'table' then return end
        if bT then t.baseTranslation = vec3(bT.x, bT.y, bT.z); t.translation = vec3(0, 0, 0) end
        if bR then t.baseRotation = vec3(bR.x, bR.y, bR.z); t.rotation = vec3(0, 0, 0) end
        if sz then t.radius = sz; t.size = sz end
        if spk.gaindB ~= nil then t.gaindB = spk.gaindB end
        if spk.coneOuterGaindB ~= nil then t.coneOuterGaindB = spk.coneOuterGaindB end
        if spk.coneInnerAngle ~= nil then t.coneInnerAngle = spk.coneInnerAngle end
        if spk.coneOuterAngle ~= nil then t.coneOuterAngle = spk.coneOuterAngle end
        if spk.lowFreqCutoff ~= nil then t.lowFreqCutoff = spk.lowFreqCutoff end
        if spk.highFreqCutoff ~= nil then t.highFreqCutoff = spk.highFreqCutoff end
        if spk.lowSlope ~= nil then t.lowSlope = spk.lowSlope end
        if spk.highSlope ~= nil then t.highSlope = spk.highSlope end
        if spk.crossoverHz ~= nil then t.crossoverHz = spk.crossoverHz end
        
        if spk.peakFreq ~= nil then t.peakFreq = spk.peakFreq end
        if spk.peakGain ~= nil then t.peakGain = spk.peakGain end
        if spk.peakQ ~= nil then t.peakQ = spk.peakQ end
        
        if spk.distThresholddB ~= nil then
          t.distThresholddB = spk.distThresholddB
          if t.distThresholdDb ~= nil then t.distThresholdDb = spk.distThresholddB end
          if t.distThreshold ~= nil then t.distThreshold = spk.distThresholddB end
          if t.overdriveThresholdDb ~= nil then t.overdriveThresholdDb = spk.distThresholddB end
          if t.overdriveThreshold ~= nil then t.overdriveThreshold = spk.distThresholddB end
        end
        if spk.distFactor ~= nil then
          t.distFactor = spk.distFactor
          if t.distortion ~= nil then t.distortion = spk.distFactor end
          if t.overdrive ~= nil then t.overdrive = spk.distFactor end
        end
        if spk.channel ~= nil then t.channel = spk.channel end
      end

      updateOrig(origSpk)
      if type(origSpk.position) == 'table' then
        updateOrig(origSpk.position)
      end
      break
    end
  end
end

local function applySpeakerLive(spk, isDragging)
  if not vEditor.vehicle or not spk then return end
  syncSpeakerToEditorVdata(spk)
  if extensions.c6g3SoundSystem and extensions.c6g3SoundSystem.updateLiveSpeakerFromEditor then
    local dragging = (isDragging == true) or (im and im.IsItemActive and im.IsItemActive())
    extensions.c6g3SoundSystem.updateLiveSpeakerFromEditor(vEditor.vehicle:getID(), spkId(spk), spk, not dragging)
  end
end

local function gizmoBeginDrag()
  local spk = state.pickedSpeaker
  if not spk then return end

  local centerWorld, workMat, frameMatIgnored, rawLenX, rawLenY = getSpeakerGlobalCenter(spk)
  if centerWorld then
    state.lastGlobalCenter = vec3(centerWorld)
  end

  if state.propertyEditing == "baseTranslation" then
    local bT = spkBaseTrans(spk)
    state.lastBaseTranslation:set(bT.x, bT.y, bT.z)
    if workMat and centerWorld then
      state.axisGizmo.fixedX = vec3(workMat:getColumn(0))
      state.axisGizmo.fixedY = vec3(workMat:getColumn(1))
      state.axisGizmo.fixedZ = vec3(workMat:getColumn(2))
      state.axisGizmo.startWorldPos = vec3(centerWorld)
      state.axisGizmo.rawLenX = rawLenX or 1
      state.axisGizmo.rawLenY = rawLenY or 1
    else
      state.axisGizmo.fixedX = nil
      state.axisGizmo.fixedY = nil
      state.axisGizmo.fixedZ = nil
      state.axisGizmo.startWorldPos = nil
      state.axisGizmo.rawLenX = nil
      state.axisGizmo.rawLenY = nil
    end
  elseif state.propertyEditing == "baseRotation" then
    local bR = spkBaseRot(spk)
    state.lastBaseRotationEuler:set(bR.x, bR.y, bR.z)
    state.axisGizmo.rawLenX = rawLenX or 1
    state.axisGizmo.rawLenY = rawLenY or 1
  elseif state.propertyEditing == "scale" then
    local sz = spkSize(spk)
    state.lastSize:set(sz, sz, sz)
  end

  state.axisGizmo.startPos = editor.getAxisGizmoTransform():inverse():getColumn(3)
  state.axisGizmo.startRot = quat(editor.getAxisGizmoTransform():toQuatF())
  dragging = true
end

local function gizmoDragging()
  local spk = state.pickedSpeaker
  if not spk then return end

  if state.propertyEditing == "baseTranslation" then
    local ax = state.axisGizmo
    if ax.fixedX and ax.fixedY and ax.fixedZ and ax.startWorldPos then
      local nowWorldPos = vec3(editor.getAxisGizmoTransform():getPosition())
      local deltaWorld = nowWorldPos - ax.startWorldPos
      local dLocal = vec3(
        deltaWorld:dot(ax.fixedX) / (ax.rawLenX or 1),
        deltaWorld:dot(ax.fixedY) / (ax.rawLenY or 1),
        deltaWorld:dot(ax.fixedZ)
      )
      spk.baseTranslation = vec3(
        state.lastBaseTranslation.x + dLocal.x,
        state.lastBaseTranslation.y + dLocal.y,
        state.lastBaseTranslation.z + dLocal.z
      )
    else
      local pos = editor.getAxisGizmoTransform():inverse():getColumn(3)
      local deltaPos = pos - state.axisGizmo.startPos
      spk.baseTranslation = vec3(
        state.lastBaseTranslation.x - deltaPos.x,
        state.lastBaseTranslation.y - deltaPos.y,
        state.lastBaseTranslation.z - deltaPos.z
      )
    end
    spk.translation = vec3(0, 0, 0)
    if type(spk.position) == 'table' then
      spk.position.baseTranslation = vec3(spk.baseTranslation.x, spk.baseTranslation.y, spk.baseTranslation.z)
      spk.position.translation = vec3(0, 0, 0)
    end

  elseif state.propertyEditing == "baseRotation" then
    local gizmoTransform = editor.getAxisGizmoTransform()
    local frameMat = getSpeakerFrame(spk)

    if frameMat then
      local fx = frameMat:getColumn(0)
      local fy = frameMat:getColumn(1)
      local fz = frameMat:getColumn(2)
      local gx = gizmoTransform:getColumn(0)
      local gy = gizmoTransform:getColumn(1)
      local gz = gizmoTransform:getColumn(2)

      local brMat_new = MatrixF(true)
      brMat_new:setColumn(0, vec3(gx:dot(fx), gx:dot(fy), gx:dot(fz)))
      brMat_new:setColumn(1, vec3(gy:dot(fx), gy:dot(fy), gy:dot(fz)))
      brMat_new:setColumn(2, vec3(gz:dot(fx), gz:dot(fy), gz:dot(fz)))

      local newRotRadians = eulerFromMatrixXYZ(brMat_new)
      spk.baseRotation = vec3(newRotRadians.x * 180 / math.pi, newRotRadians.y * 180 / math.pi, newRotRadians.z * 180 / math.pi)
      spk.rotation = vec3(0, 0, 0)
      
      if type(spk.position) == 'table' then
        spk.position.baseRotation = vec3(spk.baseRotation.x, spk.baseRotation.y, spk.baseRotation.z)
        spk.position.rotation = vec3(0, 0, 0)
      end

      if state.lastGlobalCenter then
        local brMat = eulerToMatrix(spk.baseRotation)
        local workMat = MatrixF(true)
        workMat:setColumn(0, frameMat:getColumn(0))
        workMat:setColumn(1, frameMat:getColumn(1))
        workMat:setColumn(2, frameMat:getColumn(2))
        workMat:mul(brMat)

        local radius = spkSize(spk) or 0
        local targetWorldTrans = state.lastGlobalCenter - frameMat:getPosition()
        if radius > 0 then
          targetWorldTrans = targetWorldTrans - workMat:getColumn(1) * radius
        end

        local rawLenX = state.axisGizmo.rawLenX or 1
        local rawLenY = state.axisGizmo.rawLenY or 1

        local cLocal = vec3(
          targetWorldTrans:dot(workMat:getColumn(0)) / rawLenX,
          targetWorldTrans:dot(workMat:getColumn(1)) / rawLenY,
          targetWorldTrans:dot(workMat:getColumn(2))
        )
        
        spk.baseTranslation = cLocal
        spk.translation = vec3(0, 0, 0)
        
        if type(spk.position) == 'table' then
          spk.position.baseTranslation = vec3(cLocal.x, cLocal.y, cLocal.z)
          spk.position.translation = vec3(0, 0, 0)
        end
      end
    end

  elseif state.propertyEditing == "scale" then
    local sclRaw = vec3(worldEditorCppApi.getAxisGizmoScale())
    local scl = amplifyAxisGizmoScale(sclRaw, scaleGizmoSpeed)
    local u = (scl.x ~= 1) and scl.x or (scl.y ~= 1) and scl.y or (scl.z ~= 1) and scl.z or 1
    local newR = math.max(1e-4, state.lastSize.x * u)
    spk.radius = newR
    spk.size = newR
    if type(spk.position) == 'table' then
      spk.position.radius = newR
      spk.position.size = newR
    end
  end

  gizmoDirty = true
end

local function gizmoEndDrag()
  dragging = false
  if state.pickedSpeaker then
    applySpeakerLive(state.pickedSpeaker, false)
  end
end

local function transformSpeaker()
  local spk = state.pickedSpeaker
  if not spk then return end

  local gizmoPos, gizmoMat = getSpeakerGlobalCenter(spk)
  if not gizmoPos then return end

  if not dragging and state.propertyEditing then
    worldEditorCppApi.setAxisGizmoRenderPlane(false)
    worldEditorCppApi.setAxisGizmoRenderPlaneHashes(false)
    worldEditorCppApi.setAxisGizmoRenderMoveGrid(false)
    editor.setAxisGizmoAlignment(editor.AxisGizmoAlignment_Local)

    local transform = gizmoMat
    editor.setAxisGizmoTransform(transform)

    local pe = state.propertyEditing
    local gizmoMode = pe == "baseTranslation" and editor.AxisGizmoMode_Translate
      or pe == "baseRotation" and editor.AxisGizmoMode_Rotate
      or pe == "scale" and editor.AxisGizmoMode_Scale
    if gizmoMode then
      editor.setAxisGizmoMode(gizmoMode)
    end
  end

  gizmoDirty = false
  if state.propertyEditing then
    editor.updateAxisGizmo(gizmoBeginDrag, gizmoEndDrag, gizmoDragging)
    editor.drawAxisGizmo()
  end
  if gizmoDirty and state.pickedSpeaker then
    applySpeakerLive(state.pickedSpeaker, true)
  end

  return dragging
end

local function pickSpeaker(transforming)
  table.clear(state.hitSpeakerRefNodes)
  state.hoveredSpeaker = nil

  local ray = getCameraMouseRay()
  local rayStartPos = ray.pos
  local rayDir = ray.dir

  local leftClicked = im.IsMouseClicked(0)
  local imguiNotHovered = not im.IsAnyItemHovered() and not im.IsWindowHovered(im.HoveredFlags_AnyWindow)

  for k, spk in pairs(state.speakersData or {}) do
    if isSpeaker(spk) then
      local worldPos, _, _ = getSpeakerGlobalCenter(spk)
      if worldPos then
        local pickR = math.max(nodeCollisionRadius * 4, spkSize(spk))

        if imguiNotHovered and not transforming then
          local tNear, _ = intersectsRay_Sphere(rayStartPos, rayDir, worldPos, pickR)
          if tNear and tNear >= 0 and tNear < maxTriggerDistance and tNear < 1e15 then
            table.insert(state.hitSpeakerRefNodes, { spk = spk, pos = worldPos, rayT = tNear })
          end
        end

        if spk ~= state.pickedSpeaker then
          debugDrawer:drawSphere(worldPos, nodeRenderRadius, regularColor, false)
        end
      end
    end
  end

  if transforming then return end

  local hits = state.hitSpeakerRefNodes
  local nh = #hits
  if nh == 0 then
    state.speakerSelectorCount = 2
    return
  end

  table.sort(hits, function(a, b) return a.rayT < b.rayT end)
  state.speakerSelectorCount = math.max(nh + 1, 2)
  local idx = clamp(state.speakerSelectorIdx, 1, nh)
  state.speakerSelectorIdx = idx

  local chosenData = hits[idx]
  local chosenSpk = chosenData.spk
  local chosenPos = chosenData.pos

  for k, spk in pairs(state.speakersData or {}) do
    if spk == chosenSpk then
      state.hoveredSpeaker = spk
      if leftClicked then
        state.pickedSpeaker = spk
        state.hoveredSpeaker = nil
        state.mode = 1
        state.propertyEditing = nil
        return
      end

      local text = string.format("speaker: %s | mode: %s", tostring(spkId(spk)), isPropAttachedSpeaker(spk) and "Prop-Attached" or "3-Node Standard")
      if spk ~= state.pickedSpeaker then
        debugDrawer:drawSphere(chosenPos, nodeHoveredRenderRadius, hoveredColor, false)
      end
      debugDrawer:drawTextAdvanced(chosenPos, text, textRedColor, true, false, textBackgroundColor, false, false)
      break
    end
  end
end

local function renderPickedSpeaker()
  local spk = state.pickedSpeaker
  if not spk then return end
  local centerWorld, wMat = getSpeakerGlobalCenter(spk)
  if not centerWorld then return end

  local radius = spkSize(spk)
  if radius < 0.02 then radius = 0.05 end

  -- Draw speaker emission sphere
  debugDrawer:drawSphere(centerWorld, radius, selectedColor, false)

  -- Draw 3D acoustic cone frustum
  local fwd = wMat:getColumn(1):normalized()
  local right = fwd:cross(vec3(0, 0, 1))
  if right:squaredLength() < 0.01 then right = fwd:cross(vec3(0, 1, 0)) end
  right = right:normalized()
  local up = right:cross(fwd):normalized()

  local L = 0.8
  local innerHalfRad = math.rad((tonumber(spk.coneInnerAngle) or 360) * 0.5)
  local outerHalfRad = math.rad((tonumber(spk.coneOuterAngle) or 360) * 0.5)
  local innerR = radius + L * math.tan(innerHalfRad)
  local outerR = radius + L * math.tan(outerHalfRad)

  local segments = 16
  for i = 0, segments - 1 do
    local t1 = i * (2 * math.pi / segments)
    local t2 = (i + 1) * (2 * math.pi / segments)

    local inP1 = centerWorld + fwd * L + right * (math.cos(t1) * innerR) + up * (math.sin(t1) * innerR)
    local inP2 = centerWorld + fwd * L + right * (math.cos(t2) * innerR) + up * (math.sin(t2) * innerR)
    debugDrawer:drawLine(inP1, inP2, ColorF(0, 1, 0, 0.85))

    local outP1 = centerWorld + fwd * L + right * (math.cos(t1) * outerR) + up * (math.sin(t1) * outerR)
    local outP2 = centerWorld + fwd * L + right * (math.cos(t2) * outerR) + up * (math.sin(t2) * outerR)
    debugDrawer:drawLine(outP1, outP2, ColorF(1, 0.65, 0, 0.85))

    if i % 4 == 0 then
      local baseP = centerWorld + right * (math.cos(t1) * radius) + up * (math.sin(t1) * radius)
      debugDrawer:drawLine(baseP, inP1, ColorF(0, 1, 0, 0.7))
      debugDrawer:drawLine(baseP, outP1, ColorF(1, 0.65, 0, 0.7))
    end
  end

  debugDrawer:drawLine(centerWorld, centerWorld + fwd * (L * 1.25), ColorF(0, 0.9, 1, 1))

  if showRefAxis then
    debugDrawer:drawLine(centerWorld, centerWorld + right * 0.4, lineRedColor)
    debugDrawer:drawLine(centerWorld, centerWorld + fwd * 0.4, lineGreenColor)
    debugDrawer:drawLine(centerWorld, centerWorld + up * 0.4, lineBlueColor)
  end

  local text = string.format("speaker: %s | Gain: %s dB | %s", tostring(spkId(spk)), tostring(spk.gaindB or 0), isPropAttachedSpeaker(spk) and "[Prop-Attached Gizmo Mode]" or "[Standard 3-Node Mode]")
  debugDrawer:drawTextAdvanced(centerWorld, text, textWhiteColor, true, false, textBackgroundColor, false, false)
end

local function removeVehicle(vehID)
  if vehID == -1 then return end
  initVehDatas[vehID] = nil
  initStates[vehID] = nil
  states[vehID] = nil
end

local function switchVehicle(vehID)
  if vehID == -1 then return end
  if not initVehDatas[vehID] then
    local vehData = core_vehicle_manager.getVehicleData(vehID)
    if vehData and vehData.vdata then
      initVehDatas[vehID] = deepcopy(vehData)
      initStates[vehID] = deepcopy(initStateTemplate)
      if vehData.vdata.c6g3SoundSystem_Speakers then
        initStates[vehID].speakersData = vehData.vdata.c6g3SoundSystem_Speakers
      elseif vehData.vdata.speakers then
        initStates[vehID].speakersData = vehData.vdata.speakers
      else
        initStates[vehID].speakersData = {}
      end
      states[vehID] = deepcopy(initStates[vehID])

      for k, spk in pairs(states[vehID].speakersData) do
        if isSpeaker(spk) then
          local bt = spkBaseTrans(spk)
          local br = spkBaseRot(spk)
          spk._orig_baseTranslation = vec3(bt.x, bt.y, bt.z)
          spk._orig_baseRotation = vec3(br.x, br.y, br.z)
          spk.baseTranslation = vec3(spk._orig_baseTranslation.x, spk._orig_baseTranslation.y, spk._orig_baseTranslation.z)
          spk.baseRotation = vec3(spk._orig_baseRotation.x, spk._orig_baseRotation.y, spk._orig_baseRotation.z)
        end
      end
    end
  end
  initVehData = initVehDatas[vehID]
  state = states[vehID]
end

local function getInitSpeaker(spk)
  if not spk then return nil end
  local vehID = vEditor.vehicle and vEditor.vehicle:getID()
  if not vehID or not initStates[vehID] then return nil end
  for k, s in pairs(initStates[vehID].speakersData) do
    if isSpeaker(s) and spkId(s) == spkId(spk) then return s end
  end
  return nil
end

-- Generates cleanly formatted JSON block for a speaker to copy/paste into your jbeam
local function generateCleanJSON(spk)
  local name = spkId(spk) or "speaker"
  local idRef = spkIdRef(spk) or ""
  local idX = spkIdX(spk) or ""
  local idY = spkIdY(spk) or ""
  local r = spkSize(spk) or 0.1
  local bR = spkBaseRot(spk)
  local bT = spkBaseTrans(spk)

  local lines = {}
  table.insert(lines, string.format('"%s": {', name))
  table.insert(lines, string.format('\t"name": "%s",', name))
  
  if isPropAttachedSpeaker(spk) then
      local tProp = spkTargetProp(spk) or ""
      table.insert(lines, string.format('\t"targetProp": "%s",', tProp))
  else
      table.insert(lines, string.format('\t"idRef": "%s",', idRef))
      table.insert(lines, string.format('\t"idX": "%s",', idX))
      table.insert(lines, string.format('\t"idY": "%s",', idY))
  end
  
  table.insert(lines, string.format('\t"radius": %.3f,', r))
  table.insert(lines, string.format('\t"baseRotation": [%.1f, %.1f, %.1f],', bR.x, bR.y, bR.z))
  table.insert(lines, string.format('\t"baseTranslation": [%.3f, %.3f, %.3f],', bT.x, bT.y, bT.z))
  table.insert(lines, string.format('\t"coneInnerAngle": %s,', spk.coneInnerAngle or 360))
  table.insert(lines, string.format('\t"coneOuterAngle": %s,', spk.coneOuterAngle or 360))
  table.insert(lines, string.format('\t"coneOuterGaindB": %s,', spk.coneOuterGaindB or -100))
  table.insert(lines, string.format('\t"lowFreqCutoff": %s,', spk.lowFreqCutoff or 20))
  table.insert(lines, string.format('\t"highFreqCutoff": %s,', spk.highFreqCutoff or 20000))
  table.insert(lines, string.format('\t"lowSlope": %s,', spk.lowSlope or 18))
  table.insert(lines, string.format('\t"highSlope": %s,', spk.highSlope or 12))
  table.insert(lines, string.format('\t"crossoverHz": %s,', spk.crossoverHz or 350))
  table.insert(lines, string.format('\t"peakFreq": %s,', spk.peakFreq or 1000))
  table.insert(lines, string.format('\t"peakGain": %.1f,', spk.peakGain or 0.0))
  table.insert(lines, string.format('\t"peakQ": %.2f,', spk.peakQ or 1.0))
  table.insert(lines, string.format('\t"distThresholddB": %.1f,', spk.distThresholddB or 0.0))
  table.insert(lines, string.format('\t"distFactor": %.1f,', spk.distFactor or 0.0))
  table.insert(lines, string.format('\t"channel": "%s",', spk.channel or "center"))
  table.insert(lines, string.format('\t"gaindB": %.1f', spk.gaindB or 0.0))
  table.insert(lines, '}')
  
  return table.concat(lines, "\n")
end

local function onVehicleEditorRenderJBeams(dtReal, dtSim, dtRaw)
  if not (windowOpen[0] and vEditor.vehicle and vEditor.vdata) then return end
  if not initVehData then switchVehicle(vEditor.vehicle:getID()) end
  if not state or not state.speakersData then return end

  renderPickedSpeaker()
  local transforming = false
  if state.pickedSpeaker and state.propertyEditing then
    transforming = transformSpeaker()
  end
  if state.mode == 2 then
    pickSpeaker(transforming)
  end
end

local rowFloat3Reserve = 248
local axisLabelCol = { im.ImVec4(1.0, 0.48, 0.48, 1.0), im.ImVec4(0.45, 0.95, 0.55, 1.0), im.ImVec4(0.55, 0.72, 1.0, 1.0) }
local uiLabelMuted = im.ImVec4(0.55, 0.62, 0.72, 1.0)
local uiBtnText = im.ImVec4(0.96, 0.97, 1.0, 1.0)
local uiBtnBg = im.ImVec4(0.10, 0.13, 0.19, 1.0)
local uiBtnBgH = im.ImVec4(0.16, 0.21, 0.31, 1.0)
local uiBtnBgA = im.ImVec4(0.22, 0.29, 0.42, 1.0)
local uiBtnOn = im.ImVec4(0.08, 0.36, 0.24, 1.0)
local uiBtnOnH = im.ImVec4(0.11, 0.44, 0.30, 1.0)
local uiBtnOnA = im.ImVec4(0.14, 0.50, 0.34, 1.0)

local function pushToolbarButtonStyle()
  im.PushStyleColor2(im.Col_Button, uiBtnBg)
  im.PushStyleColor2(im.Col_ButtonHovered, uiBtnBgH)
  im.PushStyleColor2(im.Col_ButtonActive, uiBtnBgA)
  im.PushStyleColor2(im.Col_Text, uiBtnText)
end
local function pushToolbarOnStyle()
  im.PushStyleColor2(im.Col_Button, uiBtnOn)
  im.PushStyleColor2(im.Col_ButtonHovered, uiBtnOnH)
  im.PushStyleColor2(im.Col_ButtonActive, uiBtnOnA)
  im.PushStyleColor2(im.Col_Text, uiBtnText)
end
local function popToolbarButtonStyle() im.PopStyleColor(4) end
local function smallButtonRaw(label)
  im.PushStyleVar2(im.StyleVar_FramePadding, im.ImVec2(6, 2))
  local pressed = im.SmallButton(label)
  im.PopStyleVar()
  return pressed
end
local function smallButton(label)
  pushToolbarButtonStyle()
  local pressed = smallButtonRaw(label)
  popToolbarButtonStyle()
  return pressed
end

local function gizmoButton(label, gizmoMode, editingKey)
  local isActive = state.propertyEditing == editingKey
  if isActive then pushToolbarOnStyle() else pushToolbarButtonStyle() end
  local pressed = smallButtonRaw(label)
  popToolbarButtonStyle()
  if pressed then
    if isActive then state.propertyEditing = nil
    else editor.setAxisGizmoMode(gizmoMode); state.propertyEditing = editingKey end
  end
  return pressed
end

local function copyArrayButton(id, fmt, x, y, z)
  im.SameLine()
  if smallButton("Copy##" .. id) then
    im.SetClipboardText(string.format('"x":' .. fmt .. ', "y":' .. fmt .. ', "z":' .. fmt, x, y, z))
  end
end

local function resetVec3Button(id, cur, init, apply)
  if not init then return end
  im.SameLine()
  if smallButton("Reset##" .. id) then
    cur:set(init.x, init.y, init.z)
    apply()
  end
end

local float3StepTableFlags = bit.bor(im.TableFlags_SizingStretchSame, im.TableFlags_BordersInnerV)
local stepRowBtnReserve = 58

local function float3InputsAndStepBlock(uid, valueArr, fmt, inputFlags, stepPtr3, applyFn, onAxisDelta, drawWidgetsRight, axisUnitSuffix)
  im.PushID1(uid)
  if im.BeginTable("##f3tbl" .. tostring(uid), drawWidgetsRight and 4 or 3, float3StepTableFlags) then
    if drawWidgetsRight then
      im.TableSetupColumn("x", im.TableColumnFlags_WidthStretch)
      im.TableSetupColumn("y", im.TableColumnFlags_WidthStretch)
      im.TableSetupColumn("z", im.TableColumnFlags_WidthStretch)
      im.TableSetupColumn("w", im.TableColumnFlags_WidthFixed, rowFloat3Reserve)
    end
    im.TableNextRow()
    local anyChanged = false
    for i = 0, 2 do
      im.TableNextColumn()
      local letter = string.sub("XYZ", i + 1, i + 1)
      local lbl = letter
      if axisUnitSuffix == "deg" then lbl = letter .. string.char(0xC2, 0xB0)
      elseif axisUnitSuffix == "m" then lbl = letter .. " m" end
      im.AlignTextToFramePadding()
      im.TextColored(axisLabelCol[i + 1], lbl)
      im.SameLine()
      im.PushItemWidth(-1)
      local ch = inputFlags and im.InputFloat("##v" .. i, valueArr[i], 0, 0, fmt, inputFlags) or im.InputFloat("##v" .. i, valueArr[i], 0, 0, fmt)
      im.PopItemWidth()
      if ch then anyChanged = true end
    end
    if anyChanged then applyFn() end
    if drawWidgetsRight then
      im.TableNextColumn()
      im.PushID1("tools")
      drawWidgetsRight()
      im.PopID()
    end
    im.TableNextRow()
    for ci = 0, 2 do
      im.TableNextColumn()
      local w = im.GetContentRegionAvail().x
      im.PushID1("s" .. tostring(ci))
      pushToolbarButtonStyle()
      local pm = smallButtonRaw("-")
      popToolbarButtonStyle()
      im.SameLine()
      im.SetNextItemWidth(math.max(36, w - stepRowBtnReserve))
      im.InputFloat("##step", stepPtr3[ci + 1], 0, 0, "%0.4f")
      im.SameLine()
      pushToolbarButtonStyle()
      local pp = smallButtonRaw("+")
      popToolbarButtonStyle()
      im.PopID()
      local s = stepPtr3[ci + 1][0]
      if pm then onAxisDelta(ci, -s) end
      if pp then onAxisDelta(ci, s) end
    end
    if drawWidgetsRight then im.TableNextColumn() end
    im.EndTable()
  end
  im.PopID()
end

local function scalarStepRow(uid, stepPtr, onDelta)
  im.PushID1(uid)
  im.PushItemWidth(-rowFloat3Reserve)
  local w = im.GetContentRegionAvail().x
  pushToolbarButtonStyle()
  local pressedM = smallButtonRaw("-")
  popToolbarButtonStyle()
  im.SameLine()
  im.SetNextItemWidth(math.max(36, w - stepRowBtnReserve))
  im.InputFloat("##step", stepPtr, 0, 0, "%0.4f")
  im.SameLine()
  pushToolbarButtonStyle()
  local pressedP = smallButtonRaw("+")
  popToolbarButtonStyle()
  im.PopItemWidth()
  im.PopID()
  local s = stepPtr[0]
  if pressedM then onDelta(-s) end
  if pressedP then onDelta(s) end
end

local function majorSectionHeader(label)
  im.Spacing()
  im.Separator()
  im.PushFont3("cairo_semibold_large")
  im.TextColored(im.ImVec4(0.92, 0.95, 1.0, 1.0), label)
  im.PopFont()
end

local function subsectionHeader(label)
  im.PushFont3("cairo_regular_medium")
  im.TextColored(im.ImVec4(0.78, 0.88, 0.98, 1.0), label)
  im.PopFont()
end

local function activeGizmoStatusLabel()
  local pe = state.propertyEditing
  if not pe then return "Gizmo: none" end
  local names = { baseTranslation = "Move", baseRotation = "Rotate", scale = "Scale (Radius)" }
  return "Gizmo: " .. (names[pe] or pe)
end

local function drawGizmoStatusTopRight()
  im.SameLine()
  local avail = im.GetContentRegionAvail().x
  local status = activeGizmoStatusLabel()
  im.PushFont3("cairo_regular_medium")
  local tw = im.CalcTextSize(status).x
  im.PopFont()
  local clearW = 72
  local gap = 6
  im.SetCursorPosX(im.GetCursorPosX() + math.max(0, avail - tw - gap - clearW))
  im.PushFont3("cairo_regular_medium")
  im.TextColored(im.ImVec4(0.78, 0.88, 0.98, 1.0), status)
  im.PopFont()
  im.SameLine()
  if smallButton("Clear##gizmoTop") then state.propertyEditing = nil end
end

-- Reusable Custom Widget: Slider paired with an adjustable Max Limit input
local function dynamicMaxSlider(id, valPtr, limitData, format)
  local avail = im.GetContentRegionAvail().x
  local maxW = 45
  
  -- The core slider
  im.PushItemWidth(avail - maxW - 5)
  local changed = im.SliderFloat("##" .. id, valPtr, limitData.min, limitData.max, format)
  im.PopItemWidth()
  
  -- The adjacent Max limit input
  im.SameLine()
  im.PushItemWidth(maxW)
  local maxPtr = im.FloatPtr(limitData.max)
  if im.InputFloat("##max_" .. id, maxPtr, 0, 0, "%.0f") then
    limitData.max = maxPtr[0]
  end
  if im.IsItemHovered() then im.SetTooltip("Slider Maximum Limit") end
  im.PopItemWidth()
  
  return changed
end

local stActionMapPushed = false

local function popSpeakerTransformerActionMap()
  if stActionMapPushed then
    popActionMap("SpeakerTransformerGizmo")
    stActionMapPushed = false
  end
end

local function updateSpeakerTransformerActionMap()
  local want = windowOpen[0] and state and state.pickedSpeaker and state.speakersData and vEditor and vEditor.editorActive
  if want and not stActionMapPushed then
    pushActionMapHighestPriority("SpeakerTransformerGizmo")
    stActionMapPushed = true
  elseif not want and stActionMapPushed then
    popSpeakerTransformerActionMap()
  end
end

local function onUpdate(dt)
  updateBeamngVehicleSelectableLock()
  if not windowOpen[0] or not vEditor or not vEditor.vehicle then
    popSpeakerTransformerActionMap()
    return
  end
  if not initVehData then switchVehicle(vEditor.vehicle:getID()) end
  updateSpeakerTransformerActionMap()

  if im.Begin(wndName, windowOpen, mainWndFlags) then
    im.PushStyleVar2(im.StyleVar_ItemSpacing, im.ImVec2(6, 4))
    if state and state.speakersData then
      local ioObj = im.GetIO()
      local maxSel = math.max(1, state.speakerSelectorCount - 1)
      state.speakerSelectorIdx = clamp(state.speakerSelectorIdx + clamp(ioObj.MouseWheel, -1, 1), 1, maxSel)

      local picking = state.mode == 2
      if picking then pushToolbarOnStyle() else pushToolbarButtonStyle() end
      if im.Button(picking and "Picking..." or "Pick Speaker") then
        if not picking then state.pickedSpeaker = nil; state.mode = 2
        else state.mode = 1 end
      end
      popToolbarButtonStyle()

      local spk = state.pickedSpeaker
      if spk then
        local initSpk = getInitSpeaker(spk)

        im.SameLine()
        im.PushFont3("cairo_regular_medium")
        im.TextColored(im.ImVec4(0.75, 0.82, 0.92, 1.0), string.format("  %s  |  Mode: %s", tostring(spkId(spk)), isPropAttachedSpeaker(spk) and "Prop-Attached (Position Fixing)" or "Standard 3-Node"))
        im.PopFont()
        
        -- MASTER COPY BUTTON INJECTION
        im.SameLine()
        pushToolbarOnStyle()
        if im.Button("Master Copy JSON") then
          local jsonStr = generateCleanJSON(spk)
          im.SetClipboardText(jsonStr)
        end
        if im.IsItemHovered() then im.SetTooltip("Copy clean JBeam dictionary to clipboard") end
        popToolbarButtonStyle()

        drawGizmoStatusTopRight()

        -- Section 1: Movement (Local)
        majorSectionHeader("Movement (Local)")
        local bT = spkBaseTrans(spk)
        inputBaseTranslation[0] = im.FloatPtr(bT.x)
        inputBaseTranslation[1] = im.FloatPtr(bT.y)
        inputBaseTranslation[2] = im.FloatPtr(bT.z)
        float3InputsAndStepBlock(
          "baseTrans",
          inputBaseTranslation,
          "%.4f",
          0,
          stepBaseTranslation,
          function()
            local nx = inputBaseTranslation[0][0]
            local ny = inputBaseTranslation[1][0]
            local nz = inputBaseTranslation[2][0]
            spk.baseTranslation = vec3(nx, ny, nz)
            spk.translation = vec3(0, 0, 0)
            if type(spk.position) == 'table' then
              spk.position.baseTranslation = vec3(nx, ny, nz)
              spk.position.translation = vec3(0, 0, 0)
            end
            applySpeakerLive(spk)
          end,
          function(axis, delta)
            local cur = spkBaseTrans(spk)
            if axis == 0 then cur.x = cur.x + delta
            elseif axis == 1 then cur.y = cur.y + delta
            elseif axis == 2 then cur.z = cur.z + delta end
            spk.baseTranslation = cur
            spk.translation = vec3(0, 0, 0)
            if type(spk.position) == 'table' then
              spk.position.baseTranslation = vec3(cur.x, cur.y, cur.z)
              spk.position.translation = vec3(0, 0, 0)
            end
            applySpeakerLive(spk)
          end,
          function()
            gizmoButton("Move##gizBTrans", editor.AxisGizmoMode_Translate, "baseTranslation")
            copyArrayButton("baseTrans", "%.4f", inputBaseTranslation[0][0], inputBaseTranslation[1][0], inputBaseTranslation[2][0])
            if initSpk then
              local iBT = spkBaseTrans(initSpk)
              resetVec3Button("baseTrans", spk.baseTranslation, iBT, function()
                spk.translation = vec3(0, 0, 0)
                if type(spk.position) == 'table' then
                  spk.position.baseTranslation = vec3(iBT.x, iBT.y, iBT.z)
                  spk.position.translation = vec3(0, 0, 0)
                end
                applySpeakerLive(spk)
              end)
            end
          end,
          "m"
        )

        -- Section 2: Rotation (Local)
        majorSectionHeader("Rotation (Local)")
        local bR = spkBaseRot(spk)
        inputBaseRotationDeg[0] = im.FloatPtr(bR.x)
        inputBaseRotationDeg[1] = im.FloatPtr(bR.y)
        inputBaseRotationDeg[2] = im.FloatPtr(bR.z)
        float3InputsAndStepBlock(
          "rot",
          inputBaseRotationDeg,
          "%.1f",
          0,
          stepBaseRotationDeg,
          function()
            local nx = mod360Deg(inputBaseRotationDeg[0][0])
            local ny = mod360Deg(inputBaseRotationDeg[1][0])
            local nz = mod360Deg(inputBaseRotationDeg[2][0])
            spk.baseRotation = vec3(nx, ny, nz)
            spk.rotation = vec3(0, 0, 0)
            if type(spk.position) == 'table' then
              spk.position.baseRotation = vec3(nx, ny, nz)
              spk.position.rotation = vec3(0, 0, 0)
            end
            applySpeakerLive(spk)
          end,
          function(axis, delta)
            local cur = spkBaseRot(spk)
            if axis == 0 then cur.x = mod360Deg(cur.x + delta)
            elseif axis == 1 then cur.y = mod360Deg(cur.y + delta)
            elseif axis == 2 then cur.z = mod360Deg(cur.z + delta) end
            spk.baseRotation = cur
            spk.rotation = vec3(0, 0, 0)
            if type(spk.position) == 'table' then
              spk.position.baseRotation = vec3(cur.x, cur.y, cur.z)
              spk.position.rotation = vec3(0, 0, 0)
            end
            applySpeakerLive(spk)
          end,
          function()
            gizmoButton("Rotate##gizBRot", editor.AxisGizmoMode_Rotate, "baseRotation")
            copyArrayButton("baseRot", "%.3f", inputBaseRotationDeg[0][0], inputBaseRotationDeg[1][0], inputBaseRotationDeg[2][0])
            if initSpk then
              local iBR = spkBaseRot(initSpk)
              resetVec3Button("baseRot", spk.baseRotation, iBR, function()
                spk.rotation = vec3(0, 0, 0)
                if type(spk.position) == 'table' then
                  spk.position.baseRotation = vec3(iBR.x, iBR.y, iBR.z)
                  spk.position.rotation = vec3(0, 0, 0)
                end
                applySpeakerLive(spk)
              end)
            end
          end,
          "deg"
        )

        -- Section 3: Dimensions & Acoustic Frustum
        majorSectionHeader("Dimensions & Acoustic Frustum")
        local radius = spkSize(spk)
        inputSizeSphere[0] = radius
        im.TextColored(axisLabelCol[1], "Radius (m)")
        im.SameLine()
        im.PushItemWidth(-rowFloat3Reserve)
        if im.InputFloat("##vSizeSph", inputSizeSphere, 0, 0, "%.4f") then
          local r = math.max(1e-4, inputSizeSphere[0])
          spk.radius = r
          spk.size = r
          if type(spk.position) == 'table' then
            spk.position.radius = r
            spk.position.size = r
          end
          applySpeakerLive(spk)
        end
        im.PopItemWidth()
        im.SameLine()
        gizmoButton("Scale##gizSizeSph", editor.AxisGizmoMode_Scale, "scale")
        scalarStepRow("sizeSph", stepSizeSphere, function(delta)
          local r = math.max(1e-4, spkSize(spk) + delta)
          spk.radius = r
          spk.size = r
          if type(spk.position) == 'table' then
            spk.position.radius = r
            spk.position.size = r
          end
          applySpeakerLive(spk)
        end)

        -- Cone angles
        local innerAng = im.FloatPtr(tonumber(spk.coneInnerAngle) or 360)
        im.Text("Inner Cone Angle")
        im.SameLine()
        im.PushItemWidth(-100)
        if im.SliderFloat("##cInnerAng", innerAng, 0.0, 360.0, "%.1f deg") then
          spk.coneInnerAngle = innerAng[0]
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        local outerAng = im.FloatPtr(tonumber(spk.coneOuterAngle) or 360)
        im.Text("Outer Cone Angle")
        im.SameLine()
        im.PushItemWidth(-100)
        if im.SliderFloat("##cOuterAng", outerAng, 0.0, 360.0, "%.1f deg") then
          spk.coneOuterAngle = outerAng[0]
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        -- Section 4: Audio Gain & Filter Tuning
        majorSectionHeader("Audio Gain & Filter Tuning")
        
        -- Stereo Routing UI
        local currentCh = spk.channel or "center"
        im.Text("Stereo Channel")
        im.SameLine(120)
        
        if currentCh == "left" then pushToolbarOnStyle() else pushToolbarButtonStyle() end
        if im.Button("Left (Ch 1)") then spk.channel = "left"; applySpeakerLive(spk) end
        popToolbarButtonStyle()
        
        im.SameLine()
        if currentCh == "center" then pushToolbarOnStyle() else pushToolbarButtonStyle() end
        if im.Button("Center (L+R)") then spk.channel = "center"; applySpeakerLive(spk) end
        popToolbarButtonStyle()

        im.SameLine()
        if currentCh == "right" then pushToolbarOnStyle() else pushToolbarButtonStyle() end
        if im.Button("Right (Ch 2)") then spk.channel = "right"; applySpeakerLive(spk) end
        popToolbarButtonStyle()
        
        -- NEW: Dedicated Subwoofer / LFE Channel
        im.SameLine()
        if currentCh == "subwoofer" then pushToolbarOnStyle() else pushToolbarButtonStyle() end
        if im.Button("Subwoofer (LFE)") then spk.channel = "subwoofer"; applySpeakerLive(spk) end
        popToolbarButtonStyle()
        
        local gain = im.FloatPtr(tonumber(spk.gaindB) or 0.0)
        im.Text("Gain (dB)")
        im.SameLine(120)
        if dynamicMaxSlider("spkGain", gain, dynLimits.gain, "%.1f dB") then
          spk.gaindB = gain[0]
          applySpeakerLive(spk)
        end

        local outerGain = im.FloatPtr(tonumber(spk.coneOuterGaindB) or -100.0)
        im.Text("Outer Gain (dB)")
        im.SameLine(120)
        if dynamicMaxSlider("spkOuterGain", outerGain, dynLimits.outerGain, "%.1f dB") then
          spk.coneOuterGaindB = outerGain[0]
          applySpeakerLive(spk)
        end

        local loCut = im.FloatPtr(tonumber(spk.lowFreqCutoff) or 20.0)
        local hiCut = im.FloatPtr(tonumber(spk.highFreqCutoff) or 20000.0)
        im.Text("Low Cutoff (Hz)")
        im.SameLine()
        im.PushItemWidth(100)
        if im.InputFloat("##spkLoCut", loCut, 0, 0, "%.0f") then
          spk.lowFreqCutoff = math.max(1, loCut[0])
          applySpeakerLive(spk)
        end
        im.PopItemWidth()
        
        im.SameLine()
        im.Text("High Cutoff (Hz)")
        im.SameLine()
        im.PushItemWidth(100)
        if im.InputFloat("##spkHiCut", hiCut, 0, 0, "%.0f") then
          spk.highFreqCutoff = math.max(1, hiCut[0])
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        local loSlope = im.FloatPtr(tonumber(spk.lowSlope) or 18.0)
        local hiSlope = im.FloatPtr(tonumber(spk.highSlope) or 12.0)
        im.Text("Low Slope (dB/o)")
        im.SameLine()
        im.PushItemWidth(100)
        if im.InputFloat("##spkLoSlope", loSlope, 0, 0, "%.0f") then
          spk.lowSlope = math.max(6, loSlope[0])
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        im.SameLine()
        im.Text("High Slope (dB/o)")
        im.SameLine()
        im.PushItemWidth(100)
        if im.InputFloat("##spkHiSlope", hiSlope, 0, 0, "%.0f") then
          spk.highSlope = math.max(6, hiSlope[0])
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        local xCut = im.FloatPtr(tonumber(spk.crossoverHz) or 350.0)
        im.Text("Crossover (Hz)")
        im.SameLine(120)
        im.PushItemWidth(100)
        if im.InputFloat("##spkXCut", xCut, 0, 0, "%.0f") then
          spk.crossoverHz = math.max(20, math.min(20000, xCut[0]))
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        -- Section 5: EQ Peak Tuning
        majorSectionHeader("Resonance Tuning")
        
        local pFreq = im.FloatPtr(tonumber(spk.peakFreq) or 1000.0)
        local pGain = im.FloatPtr(tonumber(spk.peakGain) or 0.0)
        local pQ = im.FloatPtr(tonumber(spk.peakQ) or 1.0)

        im.Text("Peak Freq (Hz)")
        im.SameLine()
        im.PushItemWidth(100)
        if im.InputFloat("##spkPkFreq", pFreq, 0, 0, "%.0f") then
          spk.peakFreq = math.max(1, pFreq[0])
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        im.Text("Peak Gain (dB)")
        im.SameLine(120)
        if dynamicMaxSlider("spkPkGain", pGain, dynLimits.peakGain, "%.1f dB") then
          spk.peakGain = pGain[0]
          applySpeakerLive(spk)
        end

        im.Text("Peak Q")
        im.SameLine()
        im.PushItemWidth(100)
        if im.InputFloat("##spkPkQ", pQ, 0.1, 1.0, "%.2f") then
          spk.peakQ = math.max(0.1, pQ[0])
          applySpeakerLive(spk)
        end
        im.PopItemWidth()

        -- Section 6: Overdrive & Distortion
        majorSectionHeader("Overdrive & Distortion")
        
        local dThreshVal = tonumber(spk.distThresholddB or spk.distThresholdDb or spk.distThreshold or spk.overdriveThresholdDb or spk.overdriveThreshold) or 0.0
        local dThresh = im.FloatPtr(dThreshVal)
        im.Text("Dist Threshold (dB)")
        im.SameLine(140)
        if dynamicMaxSlider("spkDistThresh", dThresh, dynLimits.distThresholddB, "%.1f dB") then
          spk.distThresholddB = dThresh[0]
          spk.distThresholdDb = dThresh[0]
          spk.distThreshold = dThresh[0]
          applySpeakerLive(spk)
        end

        local dFactorVal = tonumber(spk.distFactor or spk.distortion or spk.overdrive or spk.distortionFactor or spk.overdriveFactor) or 0.0
        local dFactor = im.FloatPtr(dFactorVal)
        im.Text("Distortion Factor")
        im.SameLine(140)
        if dynamicMaxSlider("spkDistFactor", dFactor, dynLimits.distFactor, "%.3f") then
          spk.distFactor = dFactor[0]
          spk.distortion = dFactor[0]
          spk.overdrive = dFactor[0]
          applySpeakerLive(spk)
        end

      else
        im.Text("No Speaker picked. Click 'Pick Speaker' above or select in 3D viewport.")
      end
    else
      im.Text("No c6g3SoundSystem speakers found on current vehicle.")
    end
    im.PopStyleVar()
  end
  im.End()
end

local function onVehicleSwitched(oldVehicle, newVehicle, player) switchVehicle(newVehicle) end
local function onVehicleSpawned(id) removeVehicle(id); switchVehicle(id) end
local function open() windowOpen[0] = true end
local function onSerialize() return { windowOpen = windowOpen[0] } end
local function onDeserialized(data) windowOpen[0] = data.windowOpen end

local function onInputGizmoKey(keyNum)
  if not windowOpen[0] then return end
  if not editor or not editor.setAxisGizmoMode then return end
  if editor.isEditorActive and not editor.isEditorActive() then return end
  local io = im.GetIO()
  if io.WantTextInput then return end
  local spk = state and state.pickedSpeaker
  if not spk or not state.speakersData then return end

  local function toggleGizmo(mode, editingKey)
    if state.propertyEditing == editingKey then state.propertyEditing = nil
    else editor.setAxisGizmoMode(mode); state.propertyEditing = editingKey end
  end

  if keyNum == 1 then toggleGizmo(editor.AxisGizmoMode_Translate, "baseTranslation")
  elseif keyNum == 2 then toggleGizmo(editor.AxisGizmoMode_Rotate, "baseRotation")
  elseif keyNum == 3 then toggleGizmo(editor.AxisGizmoMode_Scale, "scale") end
end

M.onVehicleEditorRenderJBeams = onVehicleEditorRenderJBeams
M.onUpdate = onUpdate
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleSpawned = onVehicleSpawned
M.open = open
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.onInputGizmoKey = onInputGizmoKey

return M