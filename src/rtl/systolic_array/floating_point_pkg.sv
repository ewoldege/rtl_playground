package floating_point_pkg;

typedef struct packed {
	logic sign;
	logic [6:0] frac;
	logic [7:0] exp;
} fl_6;

endpackage