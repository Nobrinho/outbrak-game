-- Normalize the actual FBX import; preserves a backup and never replaces gameplay volumes.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local metadata = HttpService:JSONDecode([==[{
  "DestinationSign": [
    {
      "name": "Kit_DestinationSign_00",
      "source": "Sign_Post",
      "center": [
        2.0999999046325684,
        2.5,
        0.0
      ],
      "size": [
        0.25,
        5.0,
        0.25
      ],
      "color": [
        104,
        92,
        80
      ],
      "material": "Wood"
    },
    {
      "name": "Kit_DestinationSign_01",
      "source": "Sign_Post.001",
      "center": [
        -2.0999999046325684,
        2.5,
        0.0
      ],
      "size": [
        0.25,
        5.0,
        0.25
      ],
      "color": [
        104,
        92,
        80
      ],
      "material": "Wood"
    },
    {
      "name": "Kit_DestinationSign_02",
      "source": "Sign_Plate",
      "center": [
        0.0,
        4.400000095367432,
        0.0
      ],
      "size": [
        5.0,
        2.1999998092651367,
        0.25
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_DestinationSign_03",
      "source": "Sign_Stripe",
      "center": [
        2.299999952316284,
        4.400000095367432,
        0.0
      ],
      "size": [
        0.2199997901916504,
        2.1999998092651367,
        0.2800000011920929
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    }
  ],
  "FieldTent": [
    {
      "name": "Kit_FieldTent_00",
      "source": "Tent_Floor",
      "center": [
        0.0,
        0.07500000298023224,
        0.0
      ],
      "size": [
        8.0,
        0.15000000596046448,
        7.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_FieldTent_01",
      "source": "Tent_Canvas",
      "center": [
        2.0,
        2.0,
        0.0
      ],
      "size": [
        4.0870771408081055,
        4.0870771408081055,
        7.0
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_FieldTent_02",
      "source": "Tent_Canvas.001",
      "center": [
        -2.0,
        2.0,
        0.0
      ],
      "size": [
        4.0870771408081055,
        4.0870771408081055,
        7.0
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_FieldTent_03",
      "source": "Tent_Pole",
      "center": [
        4.0,
        0.30000001192092896,
        0.0
      ],
      "size": [
        0.1400001049041748,
        0.6000000238418579,
        0.14000000059604645
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_FieldTent_04",
      "source": "Tent_Pole.001",
      "center": [
        0.0,
        2.049999952316284,
        0.0
      ],
      "size": [
        0.14000000059604645,
        4.099999904632568,
        0.14000000059604645
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_FieldTent_05",
      "source": "Tent_Pole.002",
      "center": [
        -4.0,
        0.30000001192092896,
        0.0
      ],
      "size": [
        0.1400001049041748,
        0.6000000238418579,
        0.14000000059604645
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_FieldTent_06",
      "source": "Tent_Ridge",
      "center": [
        0.0,
        4.0,
        0.0
      ],
      "size": [
        0.11999999731779099,
        0.11999988555908203,
        7.400000095367432
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    }
  ],
  "Floodlight": [
    {
      "name": "Kit_Floodlight_00",
      "source": "Lamp_Base",
      "center": [
        0.0,
        0.10000000149011612,
        0.0
      ],
      "size": [
        2.0,
        0.20000000298023224,
        2.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Floodlight_01",
      "source": "Lamp_Pole",
      "center": [
        0.0,
        3.5,
        0.0
      ],
      "size": [
        0.23999999463558197,
        7.0,
        0.23999999463558197
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_Floodlight_02",
      "source": "Lamp_Housing",
      "center": [
        0.0,
        7.0,
        0.0
      ],
      "size": [
        2.0,
        1.0,
        0.5
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Floodlight_03",
      "source": "Lamp_Lens",
      "center": [
        0.0,
        7.0,
        -0.30000001192092896
      ],
      "size": [
        1.7000000476837158,
        0.6499996185302734,
        0.07999998331069946
      ],
      "color": [
        236,
        232,
        222
      ],
      "material": "Cream"
    }
  ],
  "Grenade": [
    {
      "name": "Kit_Grenade_00",
      "source": "Grenade_Body",
      "center": [
        0.0,
        0.44999998807907104,
        0.0
      ],
      "size": [
        0.7608452439308167,
        0.8500000238418579,
        0.800000011920929
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_Grenade_01",
      "source": "Grenade_Neck",
      "center": [
        0.0,
        0.9800000190734863,
        0.0
      ],
      "size": [
        0.4000000059604645,
        0.2200000286102295,
        0.4000000059604645
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Grenade_02",
      "source": "Grenade_Lever",
      "center": [
        -0.34999996423721313,
        0.8500000238418579,
        0.0
      ],
      "size": [
        0.39971527457237244,
        0.9011757373809814,
        0.2199999988079071
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    }
  ],
  "Helipad": [
    {
      "name": "Kit_Helipad_00",
      "source": "Pad_Base",
      "center": [
        0.0,
        0.125,
        0.0
      ],
      "size": [
        18.0,
        0.25,
        18.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Helipad_01",
      "source": "Pad_Ring",
      "center": [
        -8.0,
        0.25999999046325684,
        0.0
      ],
      "size": [
        0.20000028610229492,
        0.019999995827674866,
        1.5
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_02",
      "source": "Pad_Ring.001",
      "center": [
        -7.846282005310059,
        0.25999999046325684,
        1.5607225894927979
      ],
      "size": [
        0.48879241943359375,
        0.019999995827674866,
        1.5101957321166992
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_03",
      "source": "Pad_Ring.002",
      "center": [
        -7.391036033630371,
        0.25999999046325684,
        3.061467409133911
      ],
      "size": [
        0.7588014602661133,
        0.019999995827674866,
        1.4623560905456543
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_04",
      "source": "Pad_Ring.003",
      "center": [
        -6.651756763458252,
        0.25999999046325684,
        4.444561958312988
      ],
      "size": [
        0.9996490478515625,
        0.019999995827674866,
        1.3583183288574219
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_05",
      "source": "Pad_Ring.004",
      "center": [
        -5.656854152679443,
        0.25999999046325684,
        5.656854152679443
      ],
      "size": [
        1.2020816802978516,
        0.019999995827674866,
        1.2020816802978516
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_06",
      "source": "Pad_Ring.005",
      "center": [
        -4.444561958312988,
        0.25999999046325684,
        6.651756763458252
      ],
      "size": [
        1.3583183288574219,
        0.019999995827674866,
        0.9996490478515625
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_07",
      "source": "Pad_Ring.006",
      "center": [
        -3.061467409133911,
        0.25999999046325684,
        7.391036033630371
      ],
      "size": [
        1.462355613708496,
        0.019999995827674866,
        0.7588005065917969
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_08",
      "source": "Pad_Ring.007",
      "center": [
        -1.5607225894927979,
        0.25999999046325684,
        7.846282005310059
      ],
      "size": [
        1.5101957321166992,
        0.019999995827674866,
        0.48879241943359375
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_09",
      "source": "Pad_Ring.008",
      "center": [
        0.0,
        0.25999999046325684,
        8.0
      ],
      "size": [
        1.5,
        0.019999995827674866,
        0.20000028610229492
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_10",
      "source": "Pad_Ring.009",
      "center": [
        1.5607225894927979,
        0.25999999046325684,
        7.846282005310059
      ],
      "size": [
        1.5101957321166992,
        0.019999995827674866,
        0.48879241943359375
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_11",
      "source": "Pad_Ring.010",
      "center": [
        3.061467409133911,
        0.25999999046325684,
        7.391036033630371
      ],
      "size": [
        1.4623560905456543,
        0.019999995827674866,
        0.7588014602661133
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_12",
      "source": "Pad_Ring.011",
      "center": [
        4.444561958312988,
        0.25999999046325684,
        6.651756763458252
      ],
      "size": [
        1.358318567276001,
        0.019999995827674866,
        0.9996490478515625
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_13",
      "source": "Pad_Ring.012",
      "center": [
        5.656854152679443,
        0.25999999046325684,
        5.656854152679443
      ],
      "size": [
        1.2020816802978516,
        0.019999995827674866,
        1.2020816802978516
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_14",
      "source": "Pad_Ring.013",
      "center": [
        6.651756763458252,
        0.25999999046325684,
        4.444561958312988
      ],
      "size": [
        0.9996490478515625,
        0.019999995827674866,
        1.358318567276001
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_15",
      "source": "Pad_Ring.014",
      "center": [
        7.391036033630371,
        0.25999999046325684,
        3.061467409133911
      ],
      "size": [
        0.7588014602661133,
        0.019999995827674866,
        1.4623560905456543
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_16",
      "source": "Pad_Ring.015",
      "center": [
        7.846282005310059,
        0.25999999046325684,
        1.5607225894927979
      ],
      "size": [
        0.48879241943359375,
        0.019999995827674866,
        1.5101960897445679
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_17",
      "source": "Pad_Ring.016",
      "center": [
        8.0,
        0.25999999046325684,
        0.0
      ],
      "size": [
        0.20000028610229492,
        0.019999995827674866,
        1.5
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_18",
      "source": "Pad_Ring.017",
      "center": [
        7.846282005310059,
        0.25999999046325684,
        -1.5607225894927979
      ],
      "size": [
        0.48879241943359375,
        0.019999995827674866,
        1.5101960897445679
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_19",
      "source": "Pad_Ring.018",
      "center": [
        7.391036033630371,
        0.25999999046325684,
        -3.061467409133911
      ],
      "size": [
        0.7588005065917969,
        0.019999995827674866,
        1.462355613708496
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_20",
      "source": "Pad_Ring.019",
      "center": [
        6.651756763458252,
        0.25999999046325684,
        -4.444561958312988
      ],
      "size": [
        0.9996490478515625,
        0.019999995827674866,
        1.3583183288574219
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_21",
      "source": "Pad_Ring.020",
      "center": [
        5.656854152679443,
        0.25999999046325684,
        -5.656854152679443
      ],
      "size": [
        1.2020816802978516,
        0.019999995827674866,
        1.2020816802978516
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_22",
      "source": "Pad_Ring.021",
      "center": [
        4.444561958312988,
        0.25999999046325684,
        -6.651756763458252
      ],
      "size": [
        1.3583183288574219,
        0.019999995827674866,
        0.9996500015258789
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_23",
      "source": "Pad_Ring.022",
      "center": [
        3.061467409133911,
        0.25999999046325684,
        -7.391036033630371
      ],
      "size": [
        1.4623560905456543,
        0.019999995827674866,
        0.7588014602661133
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_24",
      "source": "Pad_Ring.023",
      "center": [
        1.5607225894927979,
        0.25999999046325684,
        -7.846282005310059
      ],
      "size": [
        1.5101957321166992,
        0.019999995827674866,
        0.48879241943359375
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_25",
      "source": "Pad_Ring.024",
      "center": [
        0.0,
        0.25999999046325684,
        -8.0
      ],
      "size": [
        1.5,
        0.019999995827674866,
        0.20000028610229492
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_26",
      "source": "Pad_Ring.025",
      "center": [
        -1.5607225894927979,
        0.25999999046325684,
        -7.846282005310059
      ],
      "size": [
        1.5101957321166992,
        0.019999995827674866,
        0.48879241943359375
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_27",
      "source": "Pad_Ring.026",
      "center": [
        -3.061467409133911,
        0.25999999046325684,
        -7.391036033630371
      ],
      "size": [
        1.4623560905456543,
        0.019999995827674866,
        0.7588014602661133
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_28",
      "source": "Pad_Ring.027",
      "center": [
        -4.444561958312988,
        0.25999999046325684,
        -6.651756763458252
      ],
      "size": [
        1.3583183288574219,
        0.019999995827674866,
        0.9996490478515625
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_29",
      "source": "Pad_Ring.028",
      "center": [
        -5.656854152679443,
        0.25999999046325684,
        -5.656854152679443
      ],
      "size": [
        1.2020816802978516,
        0.019999995827674866,
        1.2020816802978516
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_30",
      "source": "Pad_Ring.029",
      "center": [
        -6.651756763458252,
        0.25999999046325684,
        -4.444561958312988
      ],
      "size": [
        0.9996490478515625,
        0.019999995827674866,
        1.3583183288574219
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_31",
      "source": "Pad_Ring.030",
      "center": [
        -7.391036033630371,
        0.25999999046325684,
        -3.061467409133911
      ],
      "size": [
        0.7588014602661133,
        0.019999995827674866,
        1.4623560905456543
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_32",
      "source": "Pad_Ring.031",
      "center": [
        -7.846282005310059,
        0.25999999046325684,
        -1.5607225894927979
      ],
      "size": [
        0.48879241943359375,
        0.019999995827674866,
        1.5101960897445679
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    },
    {
      "name": "Kit_Helipad_33",
      "source": "Pad_H",
      "center": [
        1.399999976158142,
        0.25999999046325684,
        0.0
      ],
      "size": [
        0.5499999523162842,
        0.019999995827674866,
        4.0
      ],
      "color": [
        236,
        232,
        222
      ],
      "material": "Cream"
    },
    {
      "name": "Kit_Helipad_34",
      "source": "Pad_H.001",
      "center": [
        -1.399999976158142,
        0.25999999046325684,
        0.0
      ],
      "size": [
        0.5499999523162842,
        0.019999995827674866,
        4.0
      ],
      "color": [
        236,
        232,
        222
      ],
      "material": "Cream"
    },
    {
      "name": "Kit_Helipad_35",
      "source": "Pad_H.002",
      "center": [
        0.0,
        0.25999999046325684,
        0.0
      ],
      "size": [
        3.299999952316284,
        0.019999995827674866,
        0.550000011920929
      ],
      "color": [
        236,
        232,
        222
      ],
      "material": "Cream"
    }
  ],
  "Medkit": [
    {
      "name": "Kit_Medkit_00",
      "source": "Medkit_Case",
      "center": [
        0.0,
        0.4000000059604645,
        0.0
      ],
      "size": [
        2.0,
        0.800000011920929,
        1.2999999523162842
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_Medkit_01",
      "source": "Medkit_Patch",
      "center": [
        0.0,
        0.8100000023841858,
        0.0
      ],
      "size": [
        0.8999999761581421,
        0.019999980926513672,
        0.8999999761581421
      ],
      "color": [
        236,
        232,
        222
      ],
      "material": "Cream"
    },
    {
      "name": "Kit_Medkit_02",
      "source": "Medkit_Cross",
      "center": [
        0.0,
        0.8299999833106995,
        0.0
      ],
      "size": [
        0.550000011920929,
        0.029999971389770508,
        0.17000000178813934
      ],
      "color": [
        180,
        40,
        40
      ],
      "material": "Medical"
    },
    {
      "name": "Kit_Medkit_03",
      "source": "Medkit_Cross.001",
      "center": [
        0.0,
        0.8299999833106995,
        0.0
      ],
      "size": [
        0.17000000178813934,
        0.029999971389770508,
        0.550000011920929
      ],
      "color": [
        180,
        40,
        40
      ],
      "material": "Medical"
    }
  ],
  "SandbagWall": [
    {
      "name": "Kit_SandbagWall_00",
      "source": "Sandbag",
      "center": [
        2.8499999046325684,
        0.3499999940395355,
        0.0
      ],
      "size": [
        2.0,
        0.699999988079071,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_01",
      "source": "Sandbag.001",
      "center": [
        0.9500000476837158,
        0.3499999940395355,
        0.0
      ],
      "size": [
        2.0,
        0.699999988079071,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_02",
      "source": "Sandbag.002",
      "center": [
        -0.9500000476837158,
        0.3499999940395355,
        0.0
      ],
      "size": [
        2.0,
        0.699999988079071,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_03",
      "source": "Sandbag.003",
      "center": [
        -2.8499999046325684,
        0.3499999940395355,
        0.0
      ],
      "size": [
        2.0,
        0.699999988079071,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_04",
      "source": "Sandbag.004",
      "center": [
        2.4000000953674316,
        1.0099999904632568,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_05",
      "source": "Sandbag.005",
      "center": [
        0.5,
        1.0099999904632568,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_06",
      "source": "Sandbag.006",
      "center": [
        -1.4000000953674316,
        1.0099999904632568,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_07",
      "source": "Sandbag.007",
      "center": [
        -3.3000001907348633,
        1.0099999904632568,
        0.0
      ],
      "size": [
        2.000000238418579,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_08",
      "source": "Sandbag.008",
      "center": [
        2.8499999046325684,
        1.6699999570846558,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_09",
      "source": "Sandbag.009",
      "center": [
        0.9500000476837158,
        1.6699999570846558,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_10",
      "source": "Sandbag.010",
      "center": [
        -0.9500000476837158,
        1.6699999570846558,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    },
    {
      "name": "Kit_SandbagWall_11",
      "source": "Sandbag.011",
      "center": [
        -2.8499999046325684,
        1.6699999570846558,
        0.0
      ],
      "size": [
        2.0,
        0.7000000476837158,
        0.949999988079071
      ],
      "color": [
        150,
        132,
        96
      ],
      "material": "Sand"
    }
  ],
  "SupplyCrate": [
    {
      "name": "Kit_SupplyCrate_00",
      "source": "Crate_Body",
      "center": [
        0.0,
        1.25,
        0.0
      ],
      "size": [
        3.0,
        2.5,
        2.4000000953674316
      ],
      "color": [
        104,
        92,
        80
      ],
      "material": "Wood"
    },
    {
      "name": "Kit_SupplyCrate_01",
      "source": "Crate_Strap",
      "center": [
        1.350000023841858,
        1.25,
        0.0
      ],
      "size": [
        0.18000006675720215,
        2.619999885559082,
        2.5199999809265137
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_SupplyCrate_02",
      "source": "Crate_Strap.001",
      "center": [
        -1.350000023841858,
        1.25,
        0.0
      ],
      "size": [
        0.18000006675720215,
        2.619999885559082,
        2.5199999809265137
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_SupplyCrate_03",
      "source": "Crate_Patch",
      "center": [
        0.0,
        1.399999976158142,
        -1.2300000190734863
      ],
      "size": [
        0.6499999761581421,
        0.5499999523162842,
        0.04999995231628418
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    }
  ],
  "Turret": [
    {
      "name": "Kit_Turret_00",
      "source": "Turret_Leg",
      "center": [
        0.0,
        0.3499999940395355,
        0.7999999523162842
      ],
      "size": [
        0.1599999964237213,
        0.7522874474525452,
        2.7839202880859375
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Turret_01",
      "source": "Turret_Leg.001",
      "center": [
        -0.6929782629013062,
        0.3499999940395355,
        -0.3997262120246887
      ],
      "size": [
        2.491440773010254,
        0.7522875666618347,
        1.529603362083435
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Turret_02",
      "source": "Turret_Leg.002",
      "center": [
        0.6925040483474731,
        0.3499999940395355,
        -0.4005473852157593
      ],
      "size": [
        2.489954948425293,
        0.7522875666618347,
        1.532365322113037
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Turret_03",
      "source": "Turret_Mast",
      "center": [
        0.0,
        1.2000000476837158,
        0.0
      ],
      "size": [
        0.5,
        2.0,
        0.5
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_Turret_04",
      "source": "Turret_Receiver",
      "center": [
        0.0,
        2.5,
        0.0
      ],
      "size": [
        1.2000000476837158,
        0.8000001907348633,
        1.7999999523162842
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_Turret_05",
      "source": "Turret_Barrel",
      "center": [
        0.0,
        2.5,
        -1.7999999523162842
      ],
      "size": [
        0.26629582047462463,
        0.2800002098083496,
        3.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_Turret_06",
      "source": "Turret_Ammo",
      "center": [
        -1.0,
        2.3499999046325684,
        0.0
      ],
      "size": [
        0.7000000476837158,
        0.6999999284744263,
        1.0
      ],
      "color": [
        255,
        204,
        0
      ],
      "material": "Marking"
    }
  ],
  "UtilityHelicopter": [
    {
      "name": "Kit_UtilityHelicopter_00",
      "source": "Heli_Fuselage",
      "center": [
        0.0,
        3.4000000953674316,
        0.0
      ],
      "size": [
        3.5999999046325684,
        3.0999996662139893,
        6.199999809265137
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_UtilityHelicopter_01",
      "source": "Heli_Windshield",
      "center": [
        0.800000011920929,
        3.9000000953674316,
        -3.119999885559082
      ],
      "size": [
        1.399999976158142,
        1.1550195217132568,
        0.29050636291503906
      ],
      "color": [
        42,
        68,
        80
      ],
      "material": "CockpitGlass"
    },
    {
      "name": "Kit_UtilityHelicopter_02",
      "source": "Heli_SideWindow",
      "center": [
        1.809999942779541,
        4.0,
        -1.25
      ],
      "size": [
        0.059999942779541016,
        1.1000001430511475,
        1.8000000715255737
      ],
      "color": [
        42,
        68,
        80
      ],
      "material": "CockpitGlass"
    },
    {
      "name": "Kit_UtilityHelicopter_03",
      "source": "Heli_Door",
      "center": [
        1.809999942779541,
        3.4499998092651367,
        1.0
      ],
      "size": [
        0.059999942779541016,
        1.999999761581421,
        1.7000000476837158
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_04",
      "source": "Heli_DoorWindow",
      "center": [
        1.850000023841858,
        4.0,
        1.0
      ],
      "size": [
        0.07999992370605469,
        0.75,
        1.2999999523162842
      ],
      "color": [
        42,
        68,
        80
      ],
      "material": "CockpitGlass"
    },
    {
      "name": "Kit_UtilityHelicopter_05",
      "source": "Heli_DoorHandle",
      "center": [
        1.8600000143051147,
        3.4000000953674316,
        1.5
      ],
      "size": [
        0.09999990463256836,
        0.07999992370605469,
        0.40000009536743164
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_06",
      "source": "Heli_Engine",
      "center": [
        0.8999999761581421,
        5.0,
        0.3999999761581421
      ],
      "size": [
        0.7000000476837158,
        0.5,
        2.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_07",
      "source": "Heli_Windshield.001",
      "center": [
        -0.800000011920929,
        3.9000000953674316,
        -3.119999885559082
      ],
      "size": [
        1.399999976158142,
        1.1550195217132568,
        0.29050636291503906
      ],
      "color": [
        42,
        68,
        80
      ],
      "material": "CockpitGlass"
    },
    {
      "name": "Kit_UtilityHelicopter_08",
      "source": "Heli_SideWindow.001",
      "center": [
        -1.809999942779541,
        4.0,
        -1.25
      ],
      "size": [
        0.059999942779541016,
        1.1000001430511475,
        1.8000000715255737
      ],
      "color": [
        42,
        68,
        80
      ],
      "material": "CockpitGlass"
    },
    {
      "name": "Kit_UtilityHelicopter_09",
      "source": "Heli_Door.001",
      "center": [
        -1.809999942779541,
        3.4499998092651367,
        1.0
      ],
      "size": [
        0.059999942779541016,
        1.999999761581421,
        1.7000000476837158
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_10",
      "source": "Heli_DoorWindow.001",
      "center": [
        -1.850000023841858,
        4.0,
        1.0
      ],
      "size": [
        0.07999992370605469,
        0.75,
        1.2999999523162842
      ],
      "color": [
        42,
        68,
        80
      ],
      "material": "CockpitGlass"
    },
    {
      "name": "Kit_UtilityHelicopter_11",
      "source": "Heli_DoorHandle.001",
      "center": [
        -1.8600000143051147,
        3.4000000953674316,
        1.5
      ],
      "size": [
        0.09999990463256836,
        0.07999992370605469,
        0.40000009536743164
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_12",
      "source": "Heli_Engine.001",
      "center": [
        -0.8999999761581421,
        5.0,
        0.3999999761581421
      ],
      "size": [
        0.7000000476837158,
        0.5,
        2.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_13",
      "source": "Heli_Nose",
      "center": [
        0.0,
        2.9000000953674316,
        -3.0
      ],
      "size": [
        2.700000047683716,
        0.5999999046325684,
        0.9000000953674316
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_UtilityHelicopter_14",
      "source": "Heli_Tail",
      "center": [
        0.0,
        3.700000286102295,
        5.800000190734863
      ],
      "size": [
        0.699999988079071,
        1.1184885501861572,
        7.029378890991211
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_UtilityHelicopter_15",
      "source": "Heli_Fin",
      "center": [
        0.0,
        4.699999809265137,
        9.199999809265137
      ],
      "size": [
        0.20000000298023224,
        2.6999998092651367,
        1.2000007629394531
      ],
      "color": [
        86,
        96,
        66
      ],
      "material": "Canvas"
    },
    {
      "name": "Kit_UtilityHelicopter_16",
      "source": "Heli_RotorMast",
      "center": [
        0.0,
        5.400000095367432,
        0.0
      ],
      "size": [
        0.36000001430511475,
        1.5,
        0.36000001430511475
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_17",
      "source": "Heli_Rotor",
      "center": [
        0.0,
        6.199999809265137,
        0.0
      ],
      "size": [
        16.0,
        0.10000038146972656,
        0.2800000011920929
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_18",
      "source": "Heli_Rotor.001",
      "center": [
        0.0,
        6.199999809265137,
        0.0
      ],
      "size": [
        0.2800006866455078,
        0.10000038146972656,
        16.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_19",
      "source": "Heli_Skid",
      "center": [
        2.200000047683716,
        1.2000000476837158,
        0.0
      ],
      "size": [
        0.25999975204467773,
        0.26000022888183594,
        7.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_20",
      "source": "Heli_SkidStrut",
      "center": [
        2.200000047683716,
        1.9000000953674316,
        -1.600000023841858
      ],
      "size": [
        0.1399998664855957,
        1.5000001192092896,
        0.1400001049041748
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_21",
      "source": "Heli_SkidStrut.001",
      "center": [
        2.200000047683716,
        1.9000000953674316,
        1.600000023841858
      ],
      "size": [
        0.1399998664855957,
        1.5000001192092896,
        0.1400001049041748
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_22",
      "source": "Heli_Skid.001",
      "center": [
        -2.200000047683716,
        1.2000000476837158,
        0.0
      ],
      "size": [
        0.25999975204467773,
        0.26000022888183594,
        7.0
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    },
    {
      "name": "Kit_UtilityHelicopter_23",
      "source": "Heli_SkidStrut.002",
      "center": [
        -2.200000047683716,
        1.9000000953674316,
        -1.600000023841858
      ],
      "size": [
        0.1399998664855957,
        1.5000001192092896,
        0.1400001049041748
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_24",
      "source": "Heli_SkidStrut.003",
      "center": [
        -2.200000047683716,
        1.9000000953674316,
        1.600000023841858
      ],
      "size": [
        0.1399998664855957,
        1.5000001192092896,
        0.1400001049041748
      ],
      "color": [
        150,
        154,
        160
      ],
      "material": "Steel"
    },
    {
      "name": "Kit_UtilityHelicopter_25",
      "source": "Heli_TailRotor",
      "center": [
        0.0,
        4.699999809265137,
        9.199999809265137
      ],
      "size": [
        0.1599999964237213,
        1.569777250289917,
        1.5697765350341797
      ],
      "color": [
        52,
        56,
        60
      ],
      "material": "Metal"
    }
  ]
}]==])
local source = assert(workspace:FindFirstChild("outbreak-kit-import"), "Import outbreak-kit-import.fbx first")
local meshes = {}
for _, p in source:GetDescendants() do
    if p:IsA("MeshPart") then meshes[p.Name] = p end
end
local previous = ReplicatedStorage:FindFirstChild("OutbreakKit")
assert(not previous, "OutbreakKit already exists; inspect it before replacing")
local kit = Instance.new("Folder")
kit.Name = "OutbreakKit"
local result = {}
local materialMap = { Canvas=Enum.Material.Fabric, Metal=Enum.Material.Metal, Steel=Enum.Material.Metal, Wood=Enum.Material.Wood, Sand=Enum.Material.Fabric, Marking=Enum.Material.SmoothPlastic, Cream=Enum.Material.SmoothPlastic, Medical=Enum.Material.SmoothPlastic, CockpitGlass=Enum.Material.Glass }
for assetName, definitions in metadata do
    local model = Instance.new("Model")
    model.Name = assetName
    for _, d in definitions do
        local imported = assert(meshes[d.name], "Missing imported mesh: " .. d.name)
        assert(imported.MeshId ~= "", "Mesh wasn't uploaded: " .. d.name)
        local p = imported:Clone()
        p:ClearAllChildren()
        p.Name = d.source
        p.Size = imported.Size / 100
        p.CFrame = CFrame.new(table.unpack(d.center)) * imported.CFrame.Rotation
        p.Color = Color3.fromRGB(table.unpack(d.color))
        p.Material = materialMap[d.material] or Enum.Material.SmoothPlastic
        p.TextureID = ""
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = true
        p:SetAttribute("SourceMesh", d.name)
        p.Parent = model
    end
    model.WorldPivot = CFrame.identity
    model:SetAttribute("CatalogAsset", assetName)
    model:SetAttribute("ImportValidated", true)
    model.Parent = kit
    local _, size = model:GetBoundingBox()
    result[assetName] = {pieces=#model:GetChildren(), size=tostring(size)}
end
kit.Parent = ReplicatedStorage
local backup = Instance.new("Folder")
backup.Name = "OutbreakKitOriginalImport"
backup.Parent = game.ServerStorage
source.Parent = backup
return result
