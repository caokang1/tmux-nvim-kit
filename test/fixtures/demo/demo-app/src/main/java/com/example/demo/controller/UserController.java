package com.example.demo.controller;

import com.example.demo.entity.User;
import com.example.demo.service.UserService;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/user")
public class UserController {

    @Autowired
    private UserService userService;

    @GetMapping("/list")
    public List<User> list() {
        return userService.listUsers();
    }

    @GetMapping(value = "/{id}")
    public User detail(@PathVariable Long id) {
        return userService.getUser(id);
    }

    @PostMapping(path = {"/save", "/create"})
    public void save(@RequestBody User user) {
        userService.saveUser(user);
    }

    @RequestMapping(value = "/search", method = RequestMethod.GET)
    public List<User> search(String keyword) {
        return userService.listUsers();
    }
}
