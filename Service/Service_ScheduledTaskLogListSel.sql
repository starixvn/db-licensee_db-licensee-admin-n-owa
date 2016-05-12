ALTER  PROCEDURE [dbo].[Service_ScheduledTaskLogListSel]  
 @Status TINYINT = NULL,  
 @PageIndex INT = 1,  
 @PageSize INT = 50  
AS  
BEGIN   
/*  
Created: 20120611@Jacob Phan  
Task : Get task log by status  
DB: DB052.[bodb_Licensee]  
  
Revisions:  
 @Status:  
  *0: Success  
  *1: Running  
  *2: Failed  
  *3: Pending   
     
  
*/  
 SET NOCOUNT ON  
   
 IF @Status IS NULL  
 BEGIN   
  WITH Paging AS(  
     SELECT ROW_NUMBER() OVER (ORDER BY  [ScheduledTaskLogId] DESC) AS RowNumber,  
      [ScheduledTaskLogId],  
      [ScheduledTaskId],  
      [Description],   
      [Status],   
      [Data],   
      [LogMessage],  
      [StartDate],   
      [FinishDate]
	  FROM dbo.[Service_ScheduledTaskLog] WITH(NOLOCK))   
  SELECT *   
  FROM Paging  
  WHERE RowNumber BETWEEN (@PageIndex-1)*@PageSize+1 AND @PageIndex*@PageSize  
  
 END  
 ELSE  
 BEGIN  
  WITH Paging AS(  
     SELECT ROW_NUMBER() OVER (ORDER BY [ScheduledTaskLogId] DESC) AS RowNumber,  
      [ScheduledTaskLogId],  
      [ScheduledTaskId],  
      [Description],   
      [Status],   
      [Data],   
      [LogMessage],  
      [StartDate],   
      [FinishDate]
	  FROM dbo.[Service_ScheduledTaskLog] WITH(NOLOCK)     
	  WHERE [Status] = @Status) 
  SELECT *   
  FROM Paging  
  WHERE RowNumber BETWEEN (@PageIndex-1)*@PageSize+1 AND @PageIndex*@PageSize  
 END  
   
 SET NOCOUNT OFF  
END   


GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogListSel] TO [bodbLicenseeNet]
GO
GRANT EXECUTE ON [dbo].[Service_ScheduledTaskLogListSel] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[Service_ScheduledTaskLogListSel] TO [vnteam] 