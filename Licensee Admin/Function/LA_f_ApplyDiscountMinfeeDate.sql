/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="1" isNested="0"></info>*/
USE bodb_licensee
GO

CREATE FUNCTION [dbo].LA_f_ApplyDiscountMinfeeDate ()
/*  
	Created: 20190320@Bruce
	Task : Apply minfee rule for discount [#109997]
	DB: DBLIC.bodb_licensee
	Revisions:
		- 20190320@Bruce: create function

*/
RETURNS DATE
AS 
BEGIN
	RETURN '20180101'
END
GO