USE [bodb_licensee]
GO

/****** Object:  StoredProcedure [dbo].[KPI_GetAllSections]    Script Date: 6/2/2014 16:10:53  ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



ALTER PROCEDURE [dbo].[KPI_GetAllSections]   
	@SectionID int = 0,
	@SectionType int = -1
AS  
  
/*  
 * Created by : 20140117@Francis 
 * Task  : Get all sections for KPI report(KPI structural re-arrangement task) 
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 	
 * Param's Explanation:    
 * 
 */  
 
BEGIN
	SET NOCOUNT ON  
	
	SELECT SectionID, SectionName, SectionType, IsDisplayed, OrderNo
	FROM KPI_Sections (NOLOCK)
	WHERE ((@SectionID = 0) OR (@SectionID <> 0 AND SectionID = @SectionID))
	AND ((@SectionType = -1) OR (@SectionType <> -1 AND SectionType = @SectionType))
	AND IsActive = 1
END



