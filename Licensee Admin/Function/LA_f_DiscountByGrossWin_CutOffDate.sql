/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_DiscountByGrossWin_CutOffDate]()
RETURNS DATE
AS

/*  
	 Created: 20211101@Percy
	 DB: DBCUST-bodb_licensee,DBLIC-bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win - CutOffDate
	 
	 Revisions:
		- 20211101@Percy: Initialize function [RedmineID: #162158]
*/

BEGIN
	DECLARE @CutOffDate DATE = '2022-01-01'
	RETURN @CutOffDate
END
GO