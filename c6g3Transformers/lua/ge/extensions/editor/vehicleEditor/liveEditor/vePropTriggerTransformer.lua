-- Prop Trigger Transformer — vehicle editor live extension for BeamNG.drive.

local M = {}

local im = ui_imgui

local wndName = "Prop Trigger Transformer"
local mainWndFlags = bit.bor(im.WindowFlags_NoBringToFrontOnFocus)
M.menuEntry = "Prop Trigger Transformer"

local windowOpen = im.BoolPtr(false)

local nodeRenderRadius = 0.02
local nodeHoveredRenderRadius = 0.03
local nodeCollisionRadius = 0.035
local maxTriggerDistance = 1000

local scaleGizmoSpeed = 2.25

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
    for k, v in pairs(row) do
        if type(k) == 'string' and k:lower() == name:lower() then return v end
    end
    if defaultIdx then return row[defaultIdx] end
    return nil
end

local function trgId(trg) return col(trg, "id", 1) or col(trg, "name", 1) end
local function isPropTrigger(trg)
    if type(trg) ~= 'table' then return false end
    local id = trgId(trg)
    return id and id ~= "id" and id ~= "name"
end

local function trgType(trg) return col(trg, "type", 3) or "box" end
local function trgIdRef(trg) return col(trg, "idRef", -1) end
local function trgIdX(trg) return col(trg, "idX", -1) end
local function trgIdY(trg) return col(trg, "idY", -1) end
local function trgBaseTrans(trg) return col(trg, "baseTranslation", 6) end
local function trgBaseRot(trg) return col(trg, "baseRotation", -1) end
local function trgSize(trg) return col(trg, "size", 4) end

local function triggerTypeStr(trg)
  return trgType(trg)
end

local function isVec3Size(s)
  if s == nil then return false end
  local t = type(s)
  if t == 'cdata' or t == 'table' then
      return type(s.x) == 'number' and type(s.y) == 'number' and type(s.z) == 'number'
  end
  return false
end

local function vec3AxisDelta(v, axis, d)
  if axis == 0 then return vec3(v.x + d, v.y, v.z) end
  if axis == 1 then return vec3(v.x, v.y + d, v.z) end
  return vec3(v.x, v.y, v.z + d)
end

local function vec3AxisSizeDelta(v, axis, d)
  local m = 1e-4
  if axis == 0 then return vec3(math.max(m, v.x + d), v.y, v.z) end
  if axis == 1 then return vec3(v.x, math.max(m, v.y + d), v.z) end
  return vec3(v.x, v.y, math.max(m, v.z + d))
end

local function imFloatPtrVal(p)
  if type(p) == 'table' and p[0] ~= nil then return p[0] end
  return p
end

local function vec3FromFloatPtr3(a, b, c)
  return vec3(imFloatPtrVal(a), imFloatPtrVal(b), imFloatPtrVal(c))
end

local function floatPtrArray3FromVec3(arr, v)
  if not v then return end
  arr[0] = im.FloatPtr(v.x or v[1] or 0)
  arr[1] = im.FloatPtr(v.y or v[2] or 0)
  arr[2] = im.FloatPtr(v.z or v[3] or 0)
end

local function formatTriggerLabel(trg)
  return string.format("trigger: %s | type: %s", tostring(trgId(trg) or "?"), tostring(triggerTypeStr(trg)))
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

local function eulerFromMatrix(m)
  local eu = m:toEulerYXZ()
  return vec3(eu.x, eu.y, eu.z)
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
  triggersData = nil,
  hitTriggerRefNodes = {},
  triggerSelectorIdx = 1,
  triggerSelectorCount = 1,
  pickedTrigger = nil,
  hoveredTrigger = nil,
  lastBaseTranslation = vec3(),
  lastBaseRotationEuler = vec3(),
  lastSize = vec3(),
  axisGizmo = {
    startPos = vec3(),
    startRot = quat(),
  },
}

local initStates = {}
local states = {}
local initVehDatas = {}

local initVehData = nil
local state = nil

local inputBaseTranslation = im.ArrayFloat(3)
local inputBaseRotationDeg = im.ArrayFloat(3)
local inputSizeVec = im.ArrayFloat(3)
local inputSizeSphere = im.FloatPtr(1)

local function step3(v)
  return { im.FloatPtr(v), im.FloatPtr(v), im.FloatPtr(v) }
end

local stepBaseTranslation = step3(0.01)
local stepBaseRotationDeg = step3(1.0)
local stepSizeBox = step3(0.01)
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
  local nodes = vEditor.vdata.nodes
  if not nodeStr or type(nodes) ~= 'table' then return 0 end
  local n = nodes[nodeStr]
  if n and n.cid then return n.cid end
  for _, node in pairs(nodes) do
    if node.id == nodeStr or node.name == nodeStr then return node.cid or 0 end
  end
  return 0
end

local function getTargetPropId(trg)
  local tProp = col(trg, "targetProp", 2)
  if not tProp or tProp == "" then return nil end
  local props = vEditor.vdata.props
  if not props then return nil end
  for _, prop in pairs(props) do
      if prop.mesh == tProp then return prop.pid end
  end
  return nil
end

local function getPropTriggerFrame(trg)
  local beObj = vEditor.vehicle
  if not beObj then return nil end
  local stObj = scenetree.findObject(beObj:getID())
  if not stObj then return nil end

  local tProp = col(trg, "targetProp", 2)
  if tProp and tProp ~= "" then
      local pid = getTargetPropId(trg)
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
      return mat
  end

  local idRef = getNodeId(trgIdRef(trg))
  local idX   = getNodeId(trgIdX(trg))
  local idY   = getNodeId(trgIdY(trg))

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
  else
      local rawPX = beObj:getNodePosition(idX)
      local rawPY = beObj:getNodePosition(idY)
      if not rawPX or not rawPY then return nil end
      local pX = vec3(rawPX)
      local pY = vec3(rawPY)
      
      local dirX = (pX - pRef):normalized()
      local dirY = (pY - pRef):normalized()
      
      local dirZ = dirX:cross(dirY):normalized()
      dirY = dirZ:cross(dirX):normalized()
      
      if dirX:squaredLength() < 0.0001 then dirX = vec3(1, 0, 0) end
      if dirY:squaredLength() < 0.0001 then dirY = vec3(0, 1, 0) end
      if dirZ:squaredLength() < 0.0001 then dirZ = vec3(0, 0, 1) end
      
      mat:setColumn(0, dirX)
      mat:setColumn(1, dirZ)
      mat:setColumn(2, dirY)
      mat:setPosition(pRefWorld)
  end
  return mat
end

local function getPropTriggerGlobalCenter(trg)
  local frameMat = getPropTriggerFrame(trg)
  if not frameMat then return nil end
  
  local rawBR = trgBaseRot(trg) or vec3(0,0,0)
  local bRot = type(rawBR) == 'table' and vec3(rawBR.x or rawBR[1] or 0, rawBR.y or rawBR[2] or 0, rawBR.z or rawBR[3] or 0) or rawBR
  local brMat = eulerToMatrix(bRot)
  
  local workMat = MatrixF(true)
  workMat:setColumn(0, frameMat:getColumn(0))
  workMat:setColumn(1, frameMat:getColumn(1))
  workMat:setColumn(2, frameMat:getColumn(2))
  workMat:mul(brMat)
  
  local bT = trgBaseTrans(trg)
  local bTx = bT and (bT.x or bT[1]) or 0
  local bTy = bT and (bT.y or bT[2]) or 0
  local bTz = bT and (bT.z or bT[3]) or 0
  
  local worldTrans = workMat:getColumn(0) * bTx
                   + workMat:getColumn(1) * bTy
                   + workMat:getColumn(2) * bTz
  
  workMat:setPosition(frameMat:getPosition() + worldTrans)
  return workMat:getPosition(), workMat, frameMat
end

local function getTriggerBoxSizeVec3(trg)
  local sz = trgSize(trg)
  if not sz then sz = col(trg, "halfSize", nil) end
  if not sz then return nil end
  local t = type(sz)
  if t == 'number' then return vec3(sz, sz, sz) end
  if t == 'cdata' or t == 'table' then
     if type(sz.x) == 'number' and type(sz.y) == 'number' and type(sz.z) == 'number' then return vec3(sz.x, sz.y, sz.z) end
     if t == 'table' and type(sz[1]) == 'number' and type(sz[2]) == 'number' and type(sz[3]) == 'number' then return vec3(sz[1], sz[2], sz[3]) end
  end
  return nil
end

local function syncTriggerToEditorVdata(trg)
  if not vEditor.vdata or not vEditor.vdata.propTriggers then return end
  local id = trgId(trg)
  if not id then return end
  for _, origTrg in pairs(vEditor.vdata.propTriggers) do
      if isPropTrigger(origTrg) and trgId(origTrg) == id then
          origTrg.baseTranslation = vec3(trg.baseTranslation.x, trg.baseTranslation.y, trg.baseTranslation.z)
          if trg.baseRotation then
              origTrg.baseRotation = vec3(trg.baseRotation.x, trg.baseRotation.y, trg.baseRotation.z)
          end
          if trg.size then
              if type(trg.size) == 'table' then
                  origTrg.size = vec3(trg.size.x, trg.size.y, trg.size.z)
              else
                  origTrg.size = trg.size
              end
          end
          if trg.type then origTrg.type = trg.type end
          break
      end
  end
end

local function applyTriggerLive(trg)
  if not vEditor.vehicle or not trg then return end
  syncTriggerToEditorVdata(trg)
  if extensions.propTriggers and extensions.propTriggers.onVehicleSpawned then
      extensions.propTriggers.onVehicleSpawned(vEditor.vehicle:getID())
  end
end

local function setTriggerShape(trg, newType)
  if trgType(trg) == newType then return end
  state.propertyEditing = nil
  
  local rawSz = trgSize(trg)
  if newType == 'sphere' then
    if type(rawSz) == 'number' then
      trg.size = math.max(1e-4, rawSz)
    else
      local sz = getTriggerBoxSizeVec3(trg)
      if sz then
        trg.size = math.max(1e-4, math.max(sz.x, math.max(sz.y, sz.z)))
      else
        trg.size = 0.5
      end
    end
  else
    if type(rawSz) == 'number' then
      trg.size = vec3(math.max(1e-4, rawSz), math.max(1e-4, rawSz), math.max(1e-4, rawSz))
    else
      local sz = getTriggerBoxSizeVec3(trg)
      if sz then
        trg.size = vec3(sz.x, sz.y, sz.z)
      else
        trg.size = vec3(0.5, 0.5, 0.5)
      end
    end
  end
  trg.type = newType
  applyTriggerLive(trg)
end

local function gizmoBeginDrag()
  local trg = state.pickedTrigger
  if not trg then return end

  local centerWorld = getPropTriggerGlobalCenter(trg)
  if centerWorld then
      state.lastGlobalCenter = vec3(centerWorld)
  end

  if state.propertyEditing == "baseTranslation" then
    local bT = trgBaseTrans(trg)
    local bx = bT and (bT.x or bT[1]) or 0
    local by = bT and (bT.y or bT[2]) or 0
    local bz = bT and (bT.z or bT[3]) or 0
    state.lastBaseTranslation:set(bx, by, bz)
  elseif state.propertyEditing == "baseRotation" then
    local bR = trgBaseRot(trg)
    local rx = bR and (bR.x or bR[1]) or 0
    local ry = bR and (bR.y or bR[2]) or 0
    local rz = bR and (bR.z or bR[3]) or 0
    state.lastBaseRotationEuler:set(rx, ry, rz)
  elseif state.propertyEditing == "scale" then
    local typeStr = triggerTypeStr(trg)
    local sz = trgSize(trg)
    if typeStr == 'sphere' and type(sz) == 'number' then
      state.lastSize:set(sz, sz, sz)
    elseif typeStr == 'box' or typeStr == 'mesh' then
      local s = getTriggerBoxSizeVec3(trg)
      if s then
        state.lastSize:set(s.x, s.y, s.z)
      end
    end
  end

  state.axisGizmo.startPos = editor.getAxisGizmoTransform():inverse():getColumn(3)
  state.axisGizmo.startRot = quat(editor.getAxisGizmoTransform():toQuatF())
  dragging = true
end

local function gizmoDragging()
  local trg = state.pickedTrigger
  if not trg then return end

  if state.propertyEditing == "baseTranslation" then
    local pos = editor.getAxisGizmoTransform():inverse():getColumn(3)
    local deltaPos = pos - state.axisGizmo.startPos
    
    trg.baseTranslation = vec3(
      state.lastBaseTranslation.x - deltaPos.x,
      state.lastBaseTranslation.y - deltaPos.y,
      state.lastBaseTranslation.z - deltaPos.z
    )
  elseif state.propertyEditing == "baseRotation" then
    local gizmoTransform = editor.getAxisGizmoTransform()
    local frameMat = getPropTriggerFrame(trg)
    
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
        trg.baseRotation = vec3(newRotRadians.x * 180 / math.pi, newRotRadians.y * 180 / math.pi, newRotRadians.z * 180 / math.pi)
        
        if state.lastGlobalCenter then
            local brMat = eulerToMatrix(trg.baseRotation)
            local workMat = MatrixF(true)
            workMat:setColumn(0, frameMat:getColumn(0))
            workMat:setColumn(1, frameMat:getColumn(1))
            workMat:setColumn(2, frameMat:getColumn(2))
            workMat:mul(brMat)
            
            local offset = state.lastGlobalCenter - frameMat:getPosition()
            local cLocal = vec3(
                offset:dot(workMat:getColumn(0)),
                offset:dot(workMat:getColumn(1)),
                offset:dot(workMat:getColumn(2))
            )
            trg.baseTranslation = cLocal
        end
    end
  elseif state.propertyEditing == "scale" then
    local sclRaw = vec3(worldEditorCppApi.getAxisGizmoScale())
    local scl = amplifyAxisGizmoScale(sclRaw, scaleGizmoSpeed)
    local typeStr = triggerTypeStr(trg)
    local sz = trgSize(trg)
    if typeStr == 'sphere' and type(sz) == 'number' then
      local u = (scl.x ~= 1) and scl.x or (scl.y ~= 1) and scl.y or (scl.z ~= 1) and scl.z or 1
      trg.size = math.max(1e-4, state.lastSize.x * u)
    elseif typeStr == 'box' or typeStr == 'mesh' then
      local s = getTriggerBoxSizeVec3(trg)
      if s then
        trg.size = vec3(
          math.max(1e-4, state.lastSize.x * scl.x),
          math.max(1e-4, state.lastSize.y * scl.y),
          math.max(1e-4, state.lastSize.z * scl.z)
        )
      end
    end
  end

  gizmoDirty = true
end

local function gizmoEndDrag()
  dragging = false
end

local function transformTrigger()
  local trg = state.pickedTrigger
  if not trg then return end

  local gizmoPos, gizmoMat = getPropTriggerGlobalCenter(trg)
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
  if gizmoDirty and state.pickedTrigger then
    applyTriggerLive(state.pickedTrigger)
  end

  return dragging
end

local tempVec = vec3()

local function pickTrigger(transforming)
  table.clear(state.hitTriggerRefNodes)
  state.hoveredTrigger = nil

  local ray = getCameraMouseRay()
  local rayStartPos = ray.pos
  local rayDir = ray.dir

  local leftClicked = im.IsMouseClicked(0)
  local imguiNotHovered = not im.IsAnyItemHovered() and not im.IsWindowHovered(im.HoveredFlags_AnyWindow)

  local veh = vEditor.vehicle

  for k, trg in pairs(state.triggersData or {}) do
    if isPropTrigger(trg) then
      local worldPos, _, _ = getPropTriggerGlobalCenter(trg)
      if worldPos then
          local pickR = nodeCollisionRadius * 4
          
          if imguiNotHovered and not transforming then
            local tNear, _ = intersectsRay_Sphere(rayStartPos, rayDir, worldPos, pickR)
            if tNear and tNear >= 0 and tNear < maxTriggerDistance and tNear < 1e15 then
              table.insert(state.hitTriggerRefNodes, { trg = trg, pos = worldPos, rayT = tNear })
            end
          end
          
          -- Don't draw the small selection dot if it's the currently picked trigger
          if trg ~= state.pickedTrigger then
            debugDrawer:drawSphere(worldPos, nodeRenderRadius, regularColor, false)
          end
      end
    end
  end

  if transforming then return end

  local hits = state.hitTriggerRefNodes
  local nh = #hits
  if nh == 0 then
    state.triggerSelectorCount = 2
    return
  end

  table.sort(hits, function(a, b) return a.rayT < b.rayT end)
  state.triggerSelectorCount = math.max(nh + 1, 2)
  local idx = clamp(state.triggerSelectorIdx, 1, nh)
  state.triggerSelectorIdx = idx

  local chosenData = hits[idx]
  local chosenTrg = chosenData.trg
  local chosenPos = chosenData.pos

  for k, trg in pairs(state.triggersData or {}) do
    if trg == chosenTrg then
      state.hoveredTrigger = trg
      if leftClicked then
        state.pickedTrigger = trg
        state.hoveredTrigger = nil
        state.mode = 1
        state.propertyEditing = nil
        return
      end

      local text = formatTriggerLabel(trg)
      if trg ~= state.pickedTrigger then
        debugDrawer:drawSphere(chosenPos, nodeHoveredRenderRadius, hoveredColor, false)
      end
      debugDrawer:drawTextAdvanced(chosenPos, text, textRedColor, true, false, textBackgroundColor, false, false)
      break
    end
  end
end

local function renderPickedTrigger()
  local trg = state.pickedTrigger
  if not trg then return end
  local centerWorld, wMat = getPropTriggerGlobalCenter(trg)
  if not centerWorld then return end
  
  local typeStr = triggerTypeStr(trg)
  local cF = ColorF(0.1, 1, 0.4, 0.25)
  local lineCol = ColorF(0.1, 1, 0.4, 1.0) -- Full opacity for better visibility
  
  if typeStr == 'box' then
    local sz = getTriggerBoxSizeVec3(trg)
    if sz then
      local hx, hy, hz = sz.x * 0.5, sz.y * 0.5, sz.z * 0.5
      local ax, ay, az = wMat:getColumn(0), wMat:getColumn(1), wMat:getColumn(2)
      
      local function dl(p1, p2) debugDrawer:drawLine(p1, p2, lineCol) end
      
      local pppp = centerWorld + ax*hx + ay*hy + az*hz
      local pppm = centerWorld + ax*hx + ay*hy - az*hz
      local ppmp = centerWorld + ax*hx - ay*hy + az*hz
      local ppmm = centerWorld + ax*hx - ay*hy - az*hz
      local pmpp = centerWorld - ax*hx + ay*hy + az*hz
      local pmpm = centerWorld - ax*hx + ay*hy - az*hz
      local pmmp = centerWorld - ax*hx - ay*hy + az*hz
      local pmmm = centerWorld - ax*hx - ay*hy - az*hz
      
      -- Draw wireframe
      dl(pppp, pppm); dl(ppmp, ppmm); dl(pmpp, pmpm); dl(pmmp, pmmm)
      dl(pppp, ppmp); dl(pppm, ppmm); dl(pmpp, pmmp); dl(pmpm, pmmm)
      dl(pppp, pmpp); dl(pppm, pmpm); dl(ppmp, pmmp); dl(ppmm, pmmm)
      
      -- Also draw cross diagonals so the box is more obviously highlighted
      dl(pppp, ppmm); dl(ppmp, pppm)
      dl(pmpp, pmmm); dl(pmmp, pmpm)
    end
  else
    local sz = trgSize(trg)
    if type(sz) == 'number' then
      -- native propTriggers treats size as diameter, so we draw with radius sz * 0.5
      debugDrawer:drawSphere(centerWorld, sz * 0.5, cF, false)
    end
  end
  
  local text = formatTriggerLabel(trg)
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
      if vehData.vdata.propTriggers then
        initStates[vehID].triggersData = vehData.vdata.propTriggers
      else
        initStates[vehID].triggersData = {}
      end
      states[vehID] = deepcopy(initStates[vehID])
      
      -- Add original state cache to triggers
      for k, trg in pairs(states[vehID].triggersData) do
        if isPropTrigger(trg) then
          local bt = trgBaseTrans(trg)
          local br = trgBaseRot(trg)
          trg._orig_baseTranslation = vec3(bt and (bt.x or bt[1]) or 0, bt and (bt.y or bt[2]) or 0, bt and (bt.z or bt[3]) or 0)
          trg._orig_baseRotation = vec3(br and (br.x or br[1]) or 0, br and (br.y or br[2]) or 0, br and (br.z or br[3]) or 0)
          
          trg.baseTranslation = vec3(trg._orig_baseTranslation.x, trg._orig_baseTranslation.y, trg._orig_baseTranslation.z)
          trg.baseRotation = vec3(trg._orig_baseRotation.x, trg._orig_baseRotation.y, trg._orig_baseRotation.z)
        end
      end
    end
  end
  initVehData = initVehDatas[vehID]
  state = states[vehID]
end

local function getInitTrigger(trg)
  if not trg then return nil end
  local vehID = vEditor.vehicle and vEditor.vehicle:getID()
  if not vehID or not initStates[vehID] then return nil end
  for k, t in pairs(initStates[vehID].triggersData) do
      if isPropTrigger(t) and trgId(t) == trgId(trg) then return t end
  end
  return nil
end

local function onVehicleEditorRenderJBeams(dtReal, dtSim, dtRaw)
  if not (windowOpen[0] and vEditor.vehicle and vEditor.vdata) then return end
  if not initVehData then switchVehicle(vEditor.vehicle:getID()) end
  if not state or not state.triggersData then return end

  renderPickedTrigger()
  local transforming = false
  if state.pickedTrigger and state.propertyEditing then
    transforming = transformTrigger()
  end
  if state.mode == 2 then
    pickTrigger(transforming)
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

local function shapeKindButton(trg, label, kind, isActive)
  if isActive then pushToolbarOnStyle() else pushToolbarButtonStyle() end
  if smallButtonRaw(label .. "##shape") then setTriggerShape(trg, kind) end
  popToolbarButtonStyle()
end

local function copyVec3Button(id, fmt, x, y, z)
  im.SameLine()
  if smallButton("Copy##" .. id) then
    im.SetClipboardText(string.format('"x":' .. fmt .. ', "y":' .. fmt .. ', "z":' .. fmt, x, y, z))
  end
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
  local names = { baseTranslation = "Move", baseRotation = "Rotate", scale = "Scale" }
  return "Gizmo: " .. (names[pe] or pe)
end

local ttActionMapPushed = false

local function popTriggerTransformerActionMap()
  if ttActionMapPushed then
    popActionMap("PropTriggerTransformerGizmo")
    ttActionMapPushed = false
  end
end

local function updateTriggerTransformerActionMap()
  local want = windowOpen[0] and state and state.pickedTrigger and state.triggersData and vEditor and vEditor.editorActive
  if want and not ttActionMapPushed then
    pushActionMapHighestPriority("PropTriggerTransformerGizmo")
    ttActionMapPushed = true
  elseif not want and ttActionMapPushed then
    popTriggerTransformerActionMap()
  end
end

local function onInputGizmoKey(keyNum)
  if not windowOpen[0] then return end
  if not editor or not editor.setAxisGizmoMode then return end
  if editor.isEditorActive and not editor.isEditorActive() then return end
  local io = im.GetIO()
  if io.WantTextInput then return end
  local trg = state and state.pickedTrigger
  if not trg or not state.triggersData then return end

  local function toggleGizmo(mode, editingKey)
    if state.propertyEditing == editingKey then state.propertyEditing = nil
    else editor.setAxisGizmoMode(mode); state.propertyEditing = editingKey end
  end

  if keyNum == 1 then toggleGizmo(editor.AxisGizmoMode_Translate, "baseTranslation")
  elseif keyNum == 2 then toggleGizmo(editor.AxisGizmoMode_Rotate, "baseRotation")
  elseif keyNum == 3 then toggleGizmo(editor.AxisGizmoMode_Scale, "scale") end
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

local function onUpdate(dt)
  updateBeamngVehicleSelectableLock()
  if not windowOpen[0] or not vEditor or not vEditor.vehicle then
    popTriggerTransformerActionMap()
    return
  end
  if not initVehData then switchVehicle(vEditor.vehicle:getID()) end
  updateTriggerTransformerActionMap()

  if im.Begin(wndName, windowOpen, mainWndFlags) then
    im.PushStyleVar2(im.StyleVar_ItemSpacing, im.ImVec2(6, 4))
    if state and state.triggersData then
      local ioObj = im.GetIO()
      local maxSel = math.max(1, state.triggerSelectorCount - 1)
      state.triggerSelectorIdx = clamp(state.triggerSelectorIdx + clamp(ioObj.MouseWheel, -1, 1), 1, maxSel)

      local picking = state.mode == 2
      if picking then pushToolbarOnStyle() else pushToolbarButtonStyle() end
      if im.Button(picking and "Picking..." or "Pick Prop Trigger") then
        if not picking then state.pickedTrigger = nil; state.mode = 2
        else state.mode = 1 end
      end
      popToolbarButtonStyle()

      local trg = state.pickedTrigger
      if trg then
        local initTrg = getInitTrigger(trg)

        im.SameLine()
        im.PushFont3("cairo_regular_medium")
        im.TextColored(im.ImVec4(0.75, 0.82, 0.92, 1.0), string.format("  %s  |  %s", tostring(trgId(trg) or "?"), triggerTypeStr(trg)))
        im.PopFont()

        im.SameLine()
        im.Dummy(im.ImVec2(10, 0))
        im.SameLine()
        if smallButton("Master Copy") then
            local idStr = trgId(trg) or ""
            local tProp = col(trg, "targetProp", 2)
            local hasTargetProp = (tProp and tProp ~= "")
            
            local typeStr = triggerTypeStr(trg) or "box"
            
            local sizeStr = ""
            local sz = trg.size
            if type(sz) == 'number' then
                sizeStr = string.format('{"x":%0.4f, "y":%0.4f, "z":%0.4f}', sz, sz, sz)
            elseif sz then
                sizeStr = string.format('{"x":%0.4f, "y":%0.4f, "z":%0.4f}', sz.x or 0, sz.y or 0, sz.z or 0)
            else
                sizeStr = '{"x":0.1000, "y":0.1000, "z":0.1000}'
            end
            
            local bt = trg.baseTranslation or vec3(0,0,0)
            local btStr = string.format('{"x":%0.4f, "y":%0.4f, "z":%0.4f}', bt.x, bt.y, bt.z)
            
            local br = trg.baseRotation or vec3(0,0,0)
            local brStr = string.format('{"x":%0.3f, "y":%0.3f, "z":%0.3f}', br.x, br.y, br.z)
            
            local outStr = ""
            if hasTargetProp then
                local actionStr = col(trg, "action", 5) or ""
                outStr = string.format('["%s", "%s", "%s", %s, "%s", %s, %s, ""]', idStr, tProp, typeStr, sizeStr, actionStr, btStr, brStr)
            else
                local idRefStr = col(trg, "idRef", 2) or ""
                local idXStr = col(trg, "idX", 3) or ""
                local idYStr = col(trg, "idY", 4) or ""
                local actionStr = col(trg, "action", 11) or ""
                outStr = string.format('["%s", "%s", "%s", "%s", "%s", %s, %s, "", "", %s, "%s"]', idStr, idRefStr, idXStr, idYStr, typeStr, sizeStr, brStr, btStr, actionStr)
            end
            im.SetClipboardText(outStr)
        end

        drawGizmoStatusTopRight()

        subsectionHeader("Shape")
        local curType = triggerTypeStr(trg)
        shapeKindButton(trg, "Box", 'box', curType == 'box')
        im.SameLine()
        shapeKindButton(trg, "Sphere", 'sphere', curType == 'sphere')
        im.SameLine()
        shapeKindButton(trg, "Mesh", 'mesh', curType == 'mesh')

        majorSectionHeader("Movement (Local)")
        
        -- Always ensure trg.baseTranslation exists as a vec3
        local bT = trgBaseTrans(trg)
        if not trg.baseTranslation then
            trg.baseTranslation = vec3(bT and (bT.x or bT[1]) or 0, bT and (bT.y or bT[2]) or 0, bT and (bT.z or bT[3]) or 0)
        end
        
        subsectionHeader("Base Translation")
        floatPtrArray3FromVec3(inputBaseTranslation, trg.baseTranslation)
        float3InputsAndStepBlock("baseTr", inputBaseTranslation, "%0.4f", nil, stepBaseTranslation, function()
          trg.baseTranslation = vec3FromFloatPtr3(inputBaseTranslation[0], inputBaseTranslation[1], inputBaseTranslation[2])
          applyTriggerLive(trg)
        end, function(axis, d)
          trg.baseTranslation = vec3AxisDelta(trg.baseTranslation, axis, d)
          applyTriggerLive(trg)
        end, function()
          gizmoButton("Gizmo##baseTr", editor.AxisGizmoMode_Translate, "baseTranslation")
          copyVec3Button("baseTr", "%0.4f", trg.baseTranslation.x, trg.baseTranslation.y, trg.baseTranslation.z)
          resetVec3Button("baseTr", trg.baseTranslation, initTrg and trg._orig_baseTranslation, function() applyTriggerLive(trg) end)
        end, nil)

        majorSectionHeader("Rotation (Local)")
        
        -- Always ensure trg.baseRotation exists as a vec3
        local bR = trgBaseRot(trg)
        if not trg.baseRotation then
            trg.baseRotation = vec3(bR and (bR.x or bR[1]) or 0, bR and (bR.y or bR[2]) or 0, bR and (bR.z or bR[3]) or 0)
        end
        
        subsectionHeader("Base Rotation")
        floatPtrArray3FromVec3(inputBaseRotationDeg, trg.baseRotation)
        float3InputsAndStepBlock("baseRot", inputBaseRotationDeg, "%0.3f", im.InputTextFlags_EnterReturnsTrue, stepBaseRotationDeg, function()
          trg.baseRotation = vec3(
            imFloatPtrVal(inputBaseRotationDeg[0]),
            imFloatPtrVal(inputBaseRotationDeg[1]),
            imFloatPtrVal(inputBaseRotationDeg[2])
          )
          applyTriggerLive(trg)
        end, function(axis, d)
          trg.baseRotation = vec3AxisDelta(trg.baseRotation, axis, d)
          applyTriggerLive(trg)
        end, function()
          local baseRotDeg = trg.baseRotation
          gizmoButton("Gizmo##baseRot", editor.AxisGizmoMode_Rotate, "baseRotation")
          copyArrayButton("baseRot", "%0.3f", baseRotDeg.x, baseRotDeg.y, baseRotDeg.z)
          resetVec3Button("baseRot", trg.baseRotation, initTrg and trg._orig_baseRotation, function() applyTriggerLive(trg) end)
        end, "deg")
        

        majorSectionHeader("Offsets (from initial load)")
        if trg._orig_baseTranslation then
            local offsetTrans = trg.baseTranslation - trg._orig_baseTranslation
            im.TextColored(uiLabelMuted, string.format("Translation Offset: x: %0.4f, y: %0.4f, z: %0.4f", offsetTrans.x, offsetTrans.y, offsetTrans.z))
            im.SameLine()
            copyVec3Button("offTr", "%0.4f", offsetTrans.x, offsetTrans.y, offsetTrans.z)
        end
        if trg._orig_baseRotation then
            local origRotDeg = trg._orig_baseRotation
            local currentRotDeg = trg.baseRotation
            local offsetRot = currentRotDeg - origRotDeg
            im.TextColored(uiLabelMuted, string.format("Rotation Offset:    x: %0.3f, y: %0.3f, z: %0.3f", offsetRot.x, offsetRot.y, offsetRot.z))
            im.SameLine()
            copyArrayButton("offRot", "%0.3f", offsetRot.x, offsetRot.y, offsetRot.z)
        end

        majorSectionHeader("Scale")
        local typeStr = triggerTypeStr(trg)
        if typeStr == 'box' or typeStr == 'mesh' then
          local sz = getTriggerBoxSizeVec3(trg)
          if sz then
            if not isVec3Size(trg.size) then trg.size = vec3(sz.x, sz.y, sz.z) end
            floatPtrArray3FromVec3(inputSizeVec, trg.size)
            float3InputsAndStepBlock("sizeBox", inputSizeVec, "%0.4f", nil, stepSizeBox, function()
              trg.size = vec3FromFloatPtr3(inputSizeVec[0], inputSizeVec[1], inputSizeVec[2])
              applyTriggerLive(trg)
            end, function(axis, d)
              trg.size = vec3AxisSizeDelta(trg.size, axis, d)
              applyTriggerLive(trg)
            end, function()
              gizmoButton("Gizmo##sizeBox", editor.AxisGizmoMode_Scale, "scale")
              copyVec3Button("size", "%0.4f", trg.size.x, trg.size.y, trg.size.z)
            end, "m")
          end
        elseif typeStr == 'sphere' and type(trg.size) == 'number' then
          inputSizeSphere[0] = trg.size
          im.TextColored(uiLabelMuted, "Radius (m)")
          im.SameLine()
          im.PushItemWidth(-rowFloat3Reserve)
          if im.InputFloat("##sizeSphere", inputSizeSphere, 0.01, 0.1, "%0.4f") then
            trg.size = inputSizeSphere[0]
            applyTriggerLive(trg)
          end
          im.PopItemWidth()
          im.SameLine()
          gizmoButton("Gizmo##sizeSphere", editor.AxisGizmoMode_Scale, "scale")
          scalarStepRow("sizeSphStep", stepSizeSphere, function(d)
            trg.size = math.max(1e-4, trg.size + d)
            applyTriggerLive(trg)
          end)
        end
      end
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

M.onVehicleEditorRenderJBeams = onVehicleEditorRenderJBeams
M.onUpdate = onUpdate
M.onVehicleSwitched = onVehicleSwitched
M.onVehicleSpawned = onVehicleSpawned
M.open = open
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized
M.onInputGizmoKey = onInputGizmoKey

return M
