# Нелинейные материалы SoftBody3D в Cgame

Физический бэкенд: **GodotPhysics3D**, не Jolt. Изменения работают в ядре Cgame,
а не в сценариях GDScript. Параметры сохраняют прежнюю физику по умолчанию.

## Что появилось

- **Упрочнение при сжатии (compression hardening)**: XPBD-контакты рёбер мягкого
  тела увеличивают упругую жёсткость при сжатии выше порога деформации,
  не меняя поведение при растяжении. Пример: сжимаемый пеноматериал.
- **Нелинейная вязкость по скорости деформации (strain-rate damping)**:
  быстрые столкновения и сжатия мягкого тела поглощают больше энергии,
  а медленная деформация может оставаться почти недемпфированной.
  Импульсы от демпфирования сохраняют общий линейный импульс пары вершин.

## Как включить

В Project Settings → Physics → 3D → Solver выберите значения или
в разделе `[physics]` своего `project.godot` добавьте:

```ini
[physics]

3d/solver/soft_body_xpbd_compliance=0.00005
3d/solver/soft_body_xpbd_compression_hardening=60.0
3d/solver/soft_body_xpbd_compression_yield_strain=0.1
3d/solver/soft_body_strain_rate_damping=2.5
3d/solver/soft_body_strain_rate_yield=1.0
```

Задавать `[physics]` второй раз не нужно — добавьте ключи в существующую
секцию. **XPBD compliance должен быть строго больше нуля**, иначе
compression hardening не активируется. Значения подбираются под масштаб,
массы и частоту симуляции конкретной игры. Перезапустите проект после изменения.

Для проверки создайте SoftBody3D, закрепите часть вершин, поместите его
между статической площадкой и падающим RigidBody3D. Сравните результат
с теми же начальными условиями при нулевых новых коэффициентах.

## Ограничения и производительность

- По умолчанию оба коэффициента равны 0, нет новых дополнительных буферов.
- При включении XPBD compression hardening использует уже существующий
  per-edge буфер нелинейного коэффициента; при включении viscosity
  добавляет проход O(число рёбер) на физический кадр без выделения памяти.
- Обе модели — приближённые edge-based constitutive laws. Это
  **не** конечные элементы FEM, повреждение/разрыв топологии или SPH жидкость.
- Не меняют физику в Jolt или 2D: доработка относится к GodotPhysics3D.
- Воспроизводите сравнения с фиксированным шагом и измеряйте
  FPS, время физических итераций, ошибки ограничений и память.

## Контракты и тесты

```bash
python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_nonlinear_materials.py' -v
python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_tension_hardening.py' -v
python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_link_damping.py' -v
```

C++ doctests: `[PhysicsXPBD]` и `[PhysicsSoftBody]` в сборке Cgame с
`tests=yes`. Python-контракты **не заменяют** компиляцию C++ или
запуск сцены в собранном движке.
