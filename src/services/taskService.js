import { v4 as uuidv4 } from "uuid";
import { taskRepository } from "../repositories/taskRepository.js";
import { Task } from "../models/taskModel.js";

/**
 * Task Service
 * Orchestrates business logic and coordinates data between Handlers and Repositories.
 */
export const taskService = {
    // Logic to create a new task
    async createNewTask(data) {
        // 1. Create a new Task entity (Model handles default configurations)
        const taskId = data.id || uuidv4();
        const newTask = new Task({
            id: taskId,
            title: data.title,
        });

        // 2. Validation logic (Place additional business rules here)

        // 3. Call Repository to persist data in the Database
        return await taskRepository.save(newTask);
    },

    // Logic to retrieve task details
    async getTaskDetails(id) {
        if (!id) throw new Error("Task ID is required.");

        const task = await taskRepository.getById(id);
        if (!task) {
            throw new Error(`Task with ID ${id} not found.`);
        }
        return task;
    },

    // Logic to retrieve the full list of tasks
    async listAllTasks() {
        return await taskRepository.getAll();
    },

    // Logic to remove a task
    async removeTask(id) {
        // Ownership check or additional business logic can be added here
        
        // Ensure the task exists before attempting deletion
        await this.getTaskDetails(id); 
        
        return await taskRepository.delete(id);
    }
};
