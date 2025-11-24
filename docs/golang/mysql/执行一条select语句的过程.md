- # 📚 MySQL 执行 SELECT 语句的完整流程详解

  ## 🔌 一、连接器（Connection Manager）

  ### 🔗 1.0 建立连接

  ![image-20251031174841668](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031174841668.png)

  ### 🔗 1.1 连接建立机制

  MySQL 支持两种连接模式，其核心区别在于 TCP 连接的生命周期：

  | **连接类型** | **默认方式**           | **TCP 连接生命周期**              | **适用场景**                 |
  | ------------ | ---------------------- | --------------------------------- | ---------------------------- |
  | **长连接**   | 需显式配置             | 建立一次连接，执行多次 SQL 后断开 | 应用程序持续访问数据库       |
  | **短连接**   | `mysql -u root -p`默认 | 执行单条 SQL 后立即断开连接       | 临时手动操作、脚本一次性任务 |

  **长连接流程**：

  1. 建立 TCP 连接（三次握手）
  
  2. 执行 SQL 语句①
  
  3. 执行 SQL 语句②

     ...
     n. 断开 TCP 连接（四次挥手）
  
  **短连接流程**：
  
  1. 建立 TCP 连接（三次握手）
  2. 执行单条 SQL 语句
  3. 断开 TCP 连接（四次挥手）
  
  
  
  一般推荐使用长连接（减少建立连接和断开连接的过程），但是长连接会有一个内存占用问题，如果长连接积累太多，会导致 Mysql服务占用内存太大，有可能会被系统强制杀掉，这样会发生 Mysql 服务异常重启的情况
  
  如何解决？

  1. 定期断开长连接（释放资源）
  2. 客户端主动重连接，Mysql 5.7 版本实现了重连函数接口，当客户端执行完一大堆操作之后，在代码里调用该函数接口，可以释放内存，重置连接，会恢复到刚刚创建完的状态
  
  
  
  ### 🔐 1.2 连接管理与身份认证
  
  - **连接池维护**：数据库通过`wait_timeout`（默认 8 小时）和`interactive_timeout`参数控制空闲连接回收
  
  - 身份校验流程：
  
    1. 验证用户名密码（存储在`mysql.user`表中）
    2. 验证失败：返回`Access denied for user`错误并终止连接
    3. 验证成功：加载用户权限快照（后续权限变更需重新连接生效）


  ​

  如果一个用户已经建立了连接，即使管理员中途修改了该用户的权限，也不影响已经存在连接的权限，修改完成后，只有再新建的连接才会使用新的权限设置

  ​

  **问题一：如何查看 MySql 服务被多少个客户端连接了**

------

  使用 **show processlist** 命令进行查看

![image-20251031174908908](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031174908908.png)

  

  **问腿二：空闲连接会一直占用着吗**

------

  不是的，Mysql定义了空闲连接的最大空闲时长，由 <u>wait_timeout</u> 参数控制，默认值是 8 小时（28880秒）如果超过，会自动断开，使用  show variables like 'wait_timeout'  命令查看默认值

![image-20251031174926499](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031174926499.png)

  我们也可以自己手动断开空闲连接，使用 kill connection + id 命令

![image-20251031174942740](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031174942740.png)

  ​

  **问题三：MySql 的连接数有限制吗？**

------

  最大连接数由 max_connections 参数控制，超过该值，会拒绝请求，并报错提示“Too many connections”

![image-20251031174957257](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031174957257.png)

  ​

  ## 📦 二、查询缓存（Query Cache）

  > **注意**：MySQL 8.0 版本已完全移除查询缓存功能，以下流程仅适用于 MySQL 5.7 及更早版本

  ### 🗄️ 2.1 缓存工作机制

  查询缓存是以 key-value 形式存在内存中的，key是 sql查询语句，value是对应结果

  ```
  客户端 → SQL请求 → 解析语句类型 → SELECT语句 → 检查缓存 → 缓存命中 → 返回结果
                                        ↓           ↓
                                    非SELECT      缓存未命中 → 执行后续流程 → 结果存入缓存
  ```

  ### ⚠️ 2.2 缓存特性与局限性

  - **存储结构**：以 SQL 语句为 KEY，查询结果为 VALUE 的内存哈希表

  - **失效机制**：关联表发生任何写操作（INSERT/UPDATE/DELETE）时，相关缓存立即失效

  - **适用场景**：只读表、低频更新表、相同 SQL 高重复执行场景

  - **性能陷阱**：高更新频率表会导致缓存频繁失效，反而增加 CPU 开销

    ​        总结：对于更新频繁的表，命中率很低，所以8.0版本直接将查询缓存删掉 了，不会再走这个阶段，之前版本如果想关闭，可以将参数 **query_cache_type** 设置成 DEMAND。



  ## 🔍 三、SQL 解析（SQL Parsing）

  ### 🔤 3.1 词法分析（Lexical Analysis）

  - **核心功能**：将 SQL 字符串的关键字识别出来，例如 SQL语句

    `select username from userinfo` 

    在分析之后，会获得4个token，其中两个关键字，select 和 from

    ![image-20251031175010202](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031175010202.png)

  ### 🌳 3.2 语法分析（Syntactic Analysis）

  - **核心功能**：构建抽象语法树（AST），验证 SQL 语法合法性

  - 错误检测：

    - 关键字拼写错误（如`SELEC * FROM user`）
    - 语法结构错误（如缺少`FROM`子句）
    - 表名 / 列名未定义（此阶段仅检查语法，不检查表是否存在）

    

  ## ▶️ 四、SQL 执行（SQL Execution）

  ### 🔧 4.1 预处理阶段（Preprocessing）

  - 语义校验：

    - 检查表和列是否存在（查询`information_schema`）
    - 验证权限（如是否有`SELECT`权限）

    如果没有表或者列，会报错

    ![image-20251031175020671](https://gitee.com/crab-crab-you/md_image/raw/master/image-20251031175020671.png)

  - 语句重写：

    - 扩展`SELECT *`为具体列名
    - 处理别名（如`SELECT u.name AS username`）
    - 解析函数和表达式（如`NOW()`、`CONCAT()`）

    

  ### 📊 4.2 优化阶段（Optimization）

  - **优化器目标**：生成成本最低的执行计划（Cost-Based Optimization）

  - 关键优化策略：

    - **索引选择**：在多个可用索引中选择代价最低的（如全表扫描 vs 索引扫描）
    - **连接顺序**：多表连接时调整表的访问顺序（小表驱动大表）
    - **条件简化**：如`WHERE id > 10 AND id < 20`简化为`id BETWEEN 11 AND 19`

    

  - **执行计划查看**：通过`EXPLAIN SELECT ...`命令可查看优化器决策结果

  ### 🚀 4.3 执行阶段（Execution）

  **主键索引查询示例**（`SELECT * FROM user WHERE id = 1`）：

  1. **执行器与存储引擎交互**：

     ```
执行器 → 调用InnoDB接口 → 定位记录 → 返回结果 → 客户端
     ```
     
     

  2. **具体步骤**：

    - 调用`read_first_record`接口，传入条件`id = 1`
     - 存储引擎通过 B + 树索引定位到对应叶节点
     - 若记录存在：返回完整行数据；若不存在：返回 "记录不存在"
     - 执行器检查记录是否符合所有条件（如存在其他过滤条件）
     - 调用`read_record`接口准备下一条记录，因主键唯一返回 - 1，循环结束
    
     

  ## 📝 五、执行流程总结

  ```
      A[连接器] -->|建立连接/校验权限| B[查询缓存]
      B -->|命中| Z[返回结果]
      B -->|未命中| C[SQL解析]
      C -->|词法/语法分析| D[预处理]
      D -->|语义校验/重写| E[优化器]
      E -->|生成执行计划| F[执行器]
      F -->|调用存储引擎接口| G[返回结果]
  ```

  ​