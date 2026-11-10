print ("Hello World")

#agregado desde branch amigo

import math
import turtle

# Configuración inicial
turtle.bgcolor("black")
turtle.shape("turtle")
turtle.speed(0)

# Dibujar los pétalos
turtle.goto(0, -40)
turtle.pendown()
h = 0
for i in range(16):
    for j in range(18):
        turtle.color("yellow")
        h += 0.005
        turtle.rt(90)
        turtle.circle(150 - j * 6, 90)
        turtle.lt(90)
        turtle.circle(150 - j * 6, 90)
        turtle.rt(180)
    turtle.circle(40, 24)

# Centro del girasol
turtle.penup()
turtle.goto(0, 0)
turtle.color("black")
turtle.fillcolor("brown")
turtle.begin_fill()
turtle.circle(0)
turtle.end_fill()

# Semillas en espiral
phi = 137.508 * (math.pi / 180.0)
for i in range(160 + 40):
    r = 4 * math.sqrt(i)
    theta = i * phi
    x = r * math.cos(theta)
    y = r * math.sin(theta)
    turtle.penup()
    turtle.goto(x, y)
    turtle.setheading(i * 137.508)
    turtle.pendown()
    if i < 160:
        turtle.stamp()

# Texto final
turtle.penup()
turtle.color("White")
turtle.write("¡Feliz día!", align="center", font=("Arial", 24, "bold"))
turtle.hideturtle()
turtle.exitonclick()
