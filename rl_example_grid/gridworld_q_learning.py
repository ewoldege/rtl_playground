from typing import Tuple, List, Optional
import numpy as np
import random


class GridWorldEnv:
    """
    Simple 5x5 grid world with a single goal and optional barriers.
    State: (row, col) with 0-based indexing.
    Actions: 0=up, 1=right, 2=down, 3=left.
    Reward scheme:
      - Goal: +10 and episode ends
      - Each step: -1
      - Bumping into wall/barrier: -5 (agent stays in place)
    """

    def __init__(
        self,
        grid_size: int = 5,
        goal_pos: Tuple[int, int] = (4, 4),
        barrier_positions: Optional[List[Tuple[int, int]]] = None,
        max_steps: int = 50,
        step_cost: float = -1.0,
        goal_reward: float = 10.0,
        bump_penalty: float = -5.0,
    ):
        self.grid_size = grid_size
        self.goal_pos = goal_pos
        self.barriers = set(barrier_positions or [])
        self.max_steps = max_steps
        self.step_cost = step_cost
        self.goal_reward = goal_reward
        self.bump_penalty = bump_penalty

        # Map action index to movement delta.
        self.action_deltas = {
            0: (-1, 0),  # up
            1: (0, 1),   # right
            2: (1, 0),   # down
            3: (0, -1),  # left
        }

        self.agent_pos: Tuple[int, int] = (0, 0)
        self.steps_taken = 0

    def reset(self, start_pos: Optional[Tuple[int, int]] = None) -> Tuple[int, int]:
        """
        Reset the environment to a starting position.
        If no start_pos is given, start at (0, 0) unless it's a barrier/goal.
        Returns the starting state as (row, col).
        """
        if start_pos is None:
            start_pos = (0, 0)

        if start_pos in self.barriers or start_pos == self.goal_pos:
            raise ValueError("Start position cannot be a barrier or the goal.")

        self.agent_pos = start_pos
        self.steps_taken = 0
        return self.agent_pos

    def state_to_index(self, state: Tuple[int, int]) -> int:
        """Convert (row, col) to a single integer index [0, grid_size^2 - 1]."""
        row, col = state
        return row * self.grid_size + col

    def index_to_state(self, index: int) -> Tuple[int, int]:
        """Convert integer index back to (row, col)."""
        return divmod(index, self.grid_size)

    def _is_in_bounds(self, pos: Tuple[int, int]) -> bool:
        """Check if (row, col) is inside the grid and not a barrier."""
        r, c = pos
        in_grid = 0 <= r < self.grid_size and 0 <= c < self.grid_size
        return in_grid and pos not in self.barriers

    def step(self, action: int) -> Tuple[Tuple[int, int], float, bool, dict]:
        """
        Take an action in the environment.
        Returns: next_state (row, col), reward, done, info.
        """
        if action not in self.action_deltas:
            raise ValueError(f"Invalid action {action}. Must be 0,1,2,3.")

        self.steps_taken += 1
        dr, dc = self.action_deltas[action]
        proposed_pos = (self.agent_pos[0] + dr, self.agent_pos[1] + dc)

        reward = self.step_cost
        next_pos = proposed_pos

        # If the move is illegal (off-grid or barrier), stay put and apply bump penalty.
        if not self._is_in_bounds(proposed_pos):
            next_pos = self.agent_pos
            reward += self.bump_penalty

        self.agent_pos = next_pos

        done = False
        if self.agent_pos == self.goal_pos:
            reward += self.goal_reward
            done = True
        elif self.steps_taken >= self.max_steps:
            done = True

        return self.agent_pos, reward, done, {}

    def render(self) -> None:
        """
        Print the grid, marking:
          - 'A' for agent
          - 'G' for goal
          - 'X' for barriers
          - '.' for empty cells
        """
        for r in range(self.grid_size):
            row_cells = []
            for c in range(self.grid_size):
                pos = (r, c)
                if pos == self.agent_pos:
                    row_cells.append("A")
                elif pos == self.goal_pos:
                    row_cells.append("G")
                elif pos in self.barriers:
                    row_cells.append("X")
                else:
                    row_cells.append(".")
            print(" ".join(row_cells))
        print()


def choose_action_epsilon_greedy(Q: np.ndarray, state_idx: int, epsilon: float) -> int:
    """
    Epsilon-greedy policy: with probability epsilon choose a random action,
    otherwise choose the action with the highest Q-value for this state.
    """
    if random.random() < epsilon:
        return random.randint(0, Q.shape[1] - 1)
    return int(np.argmax(Q[state_idx]))


def train_q_learning(
    env: GridWorldEnv,
    num_episodes: int = 500,
    alpha: float = 0.1,
    gamma: float = 0.99,
    epsilon_start: float = 0.2,
    epsilon_min: float = 0.05,
    epsilon_decay: float = 0.995,
):
    """
    Q-learning update:
      Q(s,a) <- Q(s,a) + alpha * (r + gamma * max_a' Q(s',a') - Q(s,a))

    Returns:
      Q: learned Q-table (num_states, num_actions)
      episode_steps: steps taken per episode
      episode_returns: total reward per episode
      successes: 1 if episode reached goal, else 0
    """
    num_states = env.grid_size * env.grid_size
    num_actions = 4
    Q = np.zeros((num_states, num_actions), dtype=np.float32)

    epsilon = epsilon_start
    episode_steps = []
    episode_returns = []
    successes = []

    for _ in range(num_episodes):
        state = env.reset()
        state_idx = env.state_to_index(state)
        done = False
        steps = 0
        total_reward = 0.0
        success = False

        while not done:
            action = choose_action_epsilon_greedy(Q, state_idx, epsilon)
            next_state, reward, done, _ = env.step(action)
            next_state_idx = env.state_to_index(next_state)

            best_next_Q = 0.0 if done else np.max(Q[next_state_idx])
            td_target = reward + gamma * best_next_Q
            td_error = td_target - Q[state_idx, action]
            Q[state_idx, action] += alpha * td_error

            total_reward += reward
            state_idx = next_state_idx
            steps += 1

            if done and env.agent_pos == env.goal_pos:
                success = True

        episode_steps.append(steps)
        episode_returns.append(total_reward)
        successes.append(1 if success else 0)

        epsilon = max(epsilon_min, epsilon * epsilon_decay)

    return Q, episode_steps, episode_returns, successes


def print_greedy_policy(env: GridWorldEnv, Q: np.ndarray):
    """
    Print the greedy policy implied by Q:
      ^ (up), > (right), v (down), < (left)
      G for goal, X for barriers
    """
    action_to_symbol = {0: "^", 1: ">", 2: "v", 3: "<"}

    for r in range(env.grid_size):
        row_syms = []
        for c in range(env.grid_size):
            pos = (r, c)
            if pos == env.goal_pos:
                row_syms.append("G")
            elif pos in env.barriers:
                row_syms.append("X")
            else:
                state_idx = env.state_to_index(pos)
                best_action = int(np.argmax(Q[state_idx]))
                row_syms.append(action_to_symbol[best_action])
        print(" ".join(row_syms))
    print()


def run_greedy_episode(env: GridWorldEnv, Q: np.ndarray, start_pos=(0, 0), max_steps=50):
    """
    Run one episode using a greedy policy (no exploration) and print the grid each step.
    """
    state = env.reset(start_pos)
    state_idx = env.state_to_index(state)
    done = False
    total_reward = 0.0
    steps = 0

    print(f"Starting greedy episode from {start_pos}")
    env.render()

    while not done and steps < max_steps:
        action = int(np.argmax(Q[state_idx]))
        next_state, reward, done, _ = env.step(action)
        next_state_idx = env.state_to_index(next_state)

        total_reward += reward
        steps += 1
        state_idx = next_state_idx

        print(f"Step {steps}: action={action}, reward={reward:.2f}")
        env.render()

    print(f"Episode finished. Steps: {steps}, Total reward: {total_reward:.2f}\n")


if __name__ == "__main__":
    goal = (4, 4)
    barriers = [(1, 1), (1, 2), (2, 1)]

    env = GridWorldEnv(goal_pos=goal, barrier_positions=barriers, max_steps=50)

    Q, episode_steps, episode_returns, successes = train_q_learning(
        env,
        num_episodes=500,
        alpha=0.1,
        gamma=0.99,
        epsilon_start=0.2,
        epsilon_min=0.05,
        epsilon_decay=0.995,
    )

    recent_steps = sum(episode_steps[-50:]) / 50
    recent_returns = sum(episode_returns[-50:]) / 50
    recent_success_rate = sum(successes[-50:]) / 50
    print(f"Average steps (last 50 episodes): {recent_steps:.2f}")
    print(f"Average return (last 50 episodes): {recent_returns:.2f}")
    print(f"Success rate (last 50 episodes): {recent_success_rate:.2f}")
    print("\nGreedy policy (arrows):")
    print_greedy_policy(env, Q)

    for start in [(0, 0), (0, 4), (4, 0)]:
        run_greedy_episode(env, Q, start_pos=start, max_steps=30)
