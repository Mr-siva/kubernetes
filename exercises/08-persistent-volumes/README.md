# Persistent Volumes & Storage

## What I Learned

### The Problem
Pods are ephemeral — when a pod dies, all data inside dies too.
Persistent Volumes = storage that **survives** pod restarts and deletion.

### 3 Objects

```
PersistentVolume (PV)        → the actual disk (auto-created in prod)
PersistentVolumeClaim (PVC)  → "I need X storage" (developer writes this)
Pod                          → mounts the PVC as a volume

Analogy:
  PV  = parking spot in the garage
  PVC = parking ticket (claims a spot)
  Pod = car (parks in the claimed spot)
```

### Static vs Dynamic Provisioning

```
Static (manual):
  Admin creates PV → Developer creates PVC → manually binds
  Used in: bare metal, legacy

Dynamic (PROD pattern — what actually happens):
  Developer creates PVC → StorageClass auto-creates PV → auto-binds
  Used in: AWS (EBS), GCP (PD), Azure (Disk), KinD (local-path)

You NEVER create PVs manually in prod.
```

### How the YAMLs Connect

```
pv.yaml                    pvc.yaml                  pod-with-pv.yaml
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────────┐
│ PersistentVolume │      │ PersistentVolume │      │ volumes:             │
│ name: my-pv      │◀─────│ Claim            │      │  - name: my-storage  │
│ capacity: 1Gi    │ auto │ name: my-pvc     │◀─────│    pvc:              │
│ hostPath:        │ bind │ request: 500Mi   │ refs │     claimName: my-pvc│
│  /tmp/k8s-storage│      │ ReadWriteOnce    │      │                      │
└──────────────────┘      └──────────────────┘      │ volumeMounts:        │
        │                         │                  │  - mountPath: /data  │
        │ actual disk             │ claims space     └──────────────────────┘
        ▼                         ▼                            │
  Node disk                 Bound to my-pv              Pod mounts at /data/
  /tmp/k8s-storage          (500Mi of 1Gi)              reads/writes files
```

**In production (dynamic provisioning) — you skip creating PV entirely:**
```
Developer writes PVC → StorageClass auto-creates PV → auto-binds → Pod mounts it
```

### Access Modes

```
ReadWriteOnce (RWO)  → one pod reads/writes (most common — EBS, local disk)
ReadOnlyMany  (ROX)  → many pods read only
ReadWriteMany (RWX)  → many pods read/write (need EFS/NFS — expensive)
```

### Reclaim Policies

```
Retain → keep data after PVC deleted (manual cleanup)
Delete → delete PV + data when PVC deleted (default for dynamic)
```

### Data Persistence Proof

```
Pod starts  → writes "Written at 14:04:30" to /data/hello.txt
Pod deleted → kubectl delete pod storage-test
Pod recreated → writes "Written at 14:08:23"
Logs show BOTH lines → data survived deletion ✅

Written at Sun Aug  2 14:04:30 UTC 2026   ← first pod
Written at Sun Aug  2 14:08:23 UTC 2026   ← second pod, old data still there
```

### StorageClass (KinD)

```bash
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

`WaitForFirstConsumer` = PV isn't created until a pod actually needs it.

---

## Key Commands

```bash
# PV & PVC
kubectl get pv
kubectl get pvc
kubectl describe pv <name>
kubectl describe pvc <name>

# StorageClass
kubectl get storageclass
kubectl get sc
kubectl describe sc <name>

# Delete (order matters)
kubectl delete pod <name>         # first
kubectl delete pvc <name>         # second (triggers PV cleanup if Delete policy)
kubectl delete pv <name>          # only needed if Retain policy
```

---

## Practice YAMLs

- `pv.yaml` — manual PersistentVolume (learning only, not used in prod)
- `pvc.yaml` — PersistentVolumeClaim (this is what you write in prod)
- `pod-with-pv.yaml` — Pod that mounts PVC and writes data

---

## Gotchas / Mistakes I Made

- Created a PV manually but PVC ignored it — StorageClass dynamically provisioned a NEW one instead
- In prod you only write PVCs, never PVs — StorageClass handles PV creation
- `kubectl get pv` showed my manual PV as "Available" (unbound) while a new auto-created PV was "Bound" — confusing at first
- Access mode `ReadWriteOnce` means one NODE, not one pod — multiple pods on same node can share it
- Reclaim policy `Delete` means data is GONE when PVC is deleted — be careful