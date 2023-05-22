require "spi"
require "mouse"
require "consumer_key"

class SPI
  def pmw3360dm_write(*values)
    GPIO.write_at(21, 0)
    write(*values)
    Machine.delay_us 20
    GPIO.write_at(21, 1)
  end
end

# Initialize a Keyboard
kbd = Keyboard.new

# `split=` should happen before `init_pins`
kbd.split = true

# If your right hand of CRKBD is the "anchor"
kbd.set_anchor(:right)

col0_pin = 4
row3_pin = 26

row3 = GPIO.new(row3_pin, GPIO::IN|GPIO::PULL_DOWN)
col0 = GPIO.new(col0_pin, GPIO::OUT)
col0.write(1)
if row3.high?
  puts "LEFT"
  rgb = RGB.new(
    0,    # pin number
    20,   # size of underglow pixel
    10,   # size of backlight pixel
    false # 32bit data will be sent to a pixel if true while 24bit if false
  )
else
  puts "RIGHT"
  rgb = RGB.new(0, 10, 19, false)
  # Track ball
  spi = SPI.new(
    unit: :RP2040_SPI0,
    frequency: 2_000_000,
    sck_pin:  22,
    cipo_pin: 20,
    copi_pin: 23,
    mode: 3
  )
  GPIO.new(21, GPIO::OUT)
  GPIO.write_at(21, 1)
  sleep_ms(50)
  begin
    # Power_Up_Reset
    spi.pmw3360dm_write(0x3A, 0x5A)
    sleep_ms(50)
    # Read and discard 0x02..0x06 registers
    [0x02, 0x03, 0x04, 0x05, 0x06].each do |reg|
      GPIO.write_at(21, 0)
      spi.write reg
      Machine.delay_us 35
      spi.read 1
      Machine.delay_us 20
      GPIO.write_at(21, 1)
    end
    sleep_ms(10)
    # Set CPI
    cpi = 200
    spi.pmw3360dm_write(0x0F|0x80, (cpi / 100) - 1)
    sleep_ms(10)
    # Set burst mode
    spi.pmw3360dm_write(0x50|0x80, 0)
    spi_valid = true
  rescue => e
    puts e, e.message
    spi_valid = false
  end
  if spi_valid
    mouse = Mouse.new(driver: spi)
    ball_move = 0
    mouse.task do |mouse, keyboard|
      GPIO.write_at(21, 0)
      mouse.driver.write(0x50)
      Machine.delay_us 35
      motion, _o, x_l, x_h, y_l, y_h = mouse.driver.read(6).bytes
      GPIO.write_at(21, 1)
      if (0 != motion & 0b10000000)
        x = x_h<<8|x_l
        y = y_h<<8|y_l
        x = -((~x & 0xffff) + 1) if 0x7FFF < x
        y = -((~y & 0xffff) + 1) if 0x7FFF < y
        if keyboard.layer == :lower
          x = 0 < x ? 1 : (x < 0 ? -1 : x)
          y = 0 < y ? 1 : (y < 0 ? -1 : y)
          USB.merge_mouse_report(0, 0, 0, y, -x)
        else
          if ball_move < 50
            ball_move += 7
            if 50 <= ball_move && keyboard.layer == :default
              keyboard.lock_layer :mouse
            end
          end
          if 0 < keyboard.modifier & 0b00100010
            # Shift key pressed -> Horizontal or Vertical only
            x.abs < y.abs ? x = 0 : y = 0
          end
          if 0 < keyboard.modifier & 0b01000100
            # Alt key pressed -> Fix the move amount
            x = 0 < x ? 2 : (x < 0 ? -2 : x)
            y = 0 < y ? 2 : (y < 0 ? -2 : y)
          end
          USB.merge_mouse_report(0, y, x, 0, 0)
        end
      else
        if 0 < ball_move && !mouse.button_pressed?
          ball_move -= 1
          keyboard.unlock_layer if ball_move == 0
        end
      end
      sleep_ms 15
    end
    kbd.append mouse
    # Start Burst Motion reading
    spi.write(0x50)
  end
end

col0.write(0)

rgb.effect = :swirl
rgb.split_sync = false
kbd.append rgb

# Initialize GPIO assign
kbd.init_pins(
  [ 29, 28, 27, row3_pin ],   # row0, row1,... respectively
  [ col0_pin, 5, 6, 7, 8, 9 ]  # col0, col1,... respectively
)

kbd.add_layer :default, %i[
  KC_ESCAPE KC_Q    KC_W    KC_E    KC_R    KC_T      KC_Y      KC_U    KC_I     KC_O     KC_P     KC_MINUS
  KC_TAB    KC_A    KC_S    KC_D    KC_F    KC_G      KC_H      KC_J    KC_K     KC_L     KC_SCLN  KC_BSPACE
  KC_LSFT   KC_Z    KC_X    KC_C    KC_V    KC_B      KC_N      KC_M    KC_COMMA KC_DOT   KC_SLASH KC_RSFT
  KC_NO     KC_VOLD KC_VOLU KC_LALT KC_LCTL LOWER_SPC RAISE_ENT SPC_CTL KC_NO    KC_NO    KC_RGUI  KC_NO
]
kbd.add_layer :raise, %i[
  KC_GRAVE  KC_EXLM KC_AT   KC_HASH KC_DLR  KC_PERC   KC_CIRC   KC_AMPR KC_ASTER KC_LPRN  KC_RPRN  KC_EQUAL
  KC_TAB    KC_LABK KC_LCBR KC_LBRC KC_LPRN KC_QUOTE  KC_LEFT   KC_DOWN KC_UP    KC_RIGHT KC_UNDS  KC_PIPE
  KC_LSFT   KC_RABK KC_RCBR KC_RBRC KC_RPRN KC_DQUO   KC_TILD   KC_BSLS KC_COMMA KC_DOT   KC_SLASH KC_RSFT
  KC_NO     RGB_MOD RGB_TOG KC_LALT KC_LCTL LOWER_SPC RAISE_ENT SPC_CTL KC_NO    KC_NO    BOOTSEL  KC_NO
]
kbd.add_layer :lower, %i[
  KC_ESCAPE KC_1    KC_2    KC_3    KC_4    KC_5      KC_6      KC_7    KC_8     KC_9     KC_0     KC_EQUAL
  KC_TAB    KC_LABK KC_LCBR KC_LBRC KC_LPRN KC_QUOTE  KC_LEFT   KC_DOWN KC_UP    KC_RIGHT KC_NO    KC_BSPACE
  KC_LSFT   KC_RABK KC_RCBR KC_RBRC KC_RPRN KC_DQUO   KC_NO     KC_BTN1 KC_BTN2  KC_NO    KC_NO    KC_COMMA
  KC_NO     RGB_SPD RGB_SPI KC_LALT KC_LCTL LOWER_SPC RAISE_ENT SPC_CTL KC_NO    KC_NO    BOOTSEL  KC_NO
]
kbd.add_layer :mouse, %i[
  KC_ESCAPE KC_Q    KC_W    KC_E    KC_R    KC_T      KC_F1     KC_F2   KC_F10   KC_F11   KC_F12   KC_MINUS
  KC_TAB    KC_A    KC_S    KC_D    KC_F    KC_G      KC_LEFT   KC_DOWN KC_UP    KC_RIGHT KC_NO    KC_BSPACE
  KC_LSFT   KC_Z    KC_X    KC_C    KC_V    KC_B      KC_NO     KC_BTN1 KC_BTN2  KC_NO    KC_NO    KC_RSFT
  KC_NO     KC_MPRV KC_MNXT KC_LALT KC_LCTL LOWER_SPC RAISE_ENT SPC_CTL KC_NO    KC_NO    UNLOCK   KC_NO
]

kbd.define_composite_key :SPC_CTL, %i(KC_SPACE KC_RCTL)

kbd.define_mode_key :RAISE_ENT, [ :KC_ENTER, :raise, 150, 150 ]
kbd.define_mode_key :LOWER_SPC, [ :KC_SPACE, :lower, 150, 150 ]
kbd.define_mode_key :UNLOCK,    [ Proc.new { kbd.unlock_layer }, nil, 300, nil ]
kbd.define_mode_key :BOOTSEL,   [ Proc.new { kbd.bootsel! }, nil, 300, nil ]

kbd.start!
