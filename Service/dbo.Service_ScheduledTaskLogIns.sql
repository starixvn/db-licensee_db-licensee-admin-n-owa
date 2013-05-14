ALTER  PROCEDURE [dbo].[Service_ScheduledTaskLogIns]  
 @ScheduledTaskId INT,  
 @Description NVARCHAR(MAX) ='',  
 @Data NVARCHAR(MAX)=''  
AS  
BEGIN   
/*  
Created: 20120611@Jacob Phan  
Task :   Create pending scheduled task log  
DB: DB052.[bodb_Licensee]  
  
Revisions:  
     
  
*/  
 SET NOCOUNT ON  
 INSERT INTO dbo.[Service_ScheduledTaskLog](ScheduledTaskId,[Description],[Data],[Status])  
 VALUES(@ScheduledTaskId,@Description,@Data,1)  
 SET NOCOUNT OFF  
END  
/*  
  
*/  

GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogIns] TO [bodbAdminNet]
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogIns] TO [bodbLicenseeNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskLogIns] TO [vnteam] 