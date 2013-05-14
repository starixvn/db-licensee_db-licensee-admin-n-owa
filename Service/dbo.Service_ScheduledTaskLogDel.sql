ALTER  PROCEDURE [dbo].[Service_ScheduledTaskLogDel]  
 @ScheduledTaskLogId INT
AS  
BEGIN   
/*  
Created: 20120611@Jacob Phan  
Task : Delete task log  
DB: DB052.[bodb_Licensee]  
  
Revisions:  
     
  
*/  
SET NOCOUNT ON  
   
 DELETE FROM dbo.[Service_ScheduledTaskLog]
 WHERE [ScheduledTaskLogId] = @ScheduledTaskLogId  
   
 SET NOCOUNT OFF  
END   
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogDel] TO [bodbAdminNet]  
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogDel] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskLogDel] TO [vnteam]  